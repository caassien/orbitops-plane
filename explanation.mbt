///|
/// A credential-free explanation for one action. `changed_fields` names the
/// fields that differ, without serializing the field values themselves.
pub(all) struct ActionExplanation {
  operation : Operation
  changed_fields : Array[String]
  predecessors : Array[ResourceId]
  snapshot_generation : Int
  policy_decision : PolicyDecision
  risk : RiskLevel
  policy_reason : PolicyReasonCode
} derive(Debug, Eq)

///|
pub(all) struct PlanExplanation {
  plan_id : PlanId
  snapshot_generation : Int
  actions : Array[ActionExplanation]
} derive(Debug, Eq)

///|
pub(all) struct ModifiedAction {
  resource : ResourceId
  before : Operation
  after : Operation
} derive(Debug, Eq)

///|
pub(all) struct OrderChange {
  resource : ResourceId
  before_index : Int
  after_index : Int
} derive(Debug, Eq)

///|
pub(all) struct RiskChange {
  resource : ResourceId
  before : RiskLevel
  after : RiskLevel
} derive(Debug, Eq)

///|
pub(all) struct PlanComparison {
  added : Array[Operation]
  removed : Array[Operation]
  modified : Array[ModifiedAction]
  reordered : Array[OrderChange]
  risk_changed : Array[RiskChange]
  before_generation : Int
  after_generation : Int
} derive(Debug, Eq)

///|
fn explanation_state_fields(
  desired : DesiredState,
  observed : ObservedState?,
) -> Array[String] {
  let fields : Array[String] = []
  match observed {
    None => fields.push("presence")
    Some(current) => {
      if desired.spec.version != current.spec.version {
        fields.push("version")
      }
      if desired.spec.replicas != current.spec.replicas {
        fields.push("replicas")
      }
      if desired.spec.config_fingerprint != current.spec.config_fingerprint {
        fields.push("config_fingerprint")
      }
      if desired.spec.enabled != current.spec.enabled {
        fields.push("enabled")
      }
      if !current.healthy {
        fields.push("healthy")
      }
    }
  }
  fields
}

///|
fn explanation_find_desired(
  desired : Array[DesiredState],
  resource : ResourceId,
) -> DesiredState? {
  for state in desired {
    if state.resource == resource {
      return Some(state)
    }
  }
  None
}

///|
fn explanation_predecessors(
  resource : ResourceId,
  dependencies : Array[(ResourceId, ResourceId)],
) -> Array[ResourceId] {
  let result : Array[ResourceId] = []
  for edge in dependencies {
    let (dependency, dependent) = edge
    if dependent == resource && !contains_resource_id(result, dependency) {
      result.push(dependency)
    }
  }
  // Repeatedly select the smallest remaining key to avoid input-order effects.
  let ordered : Array[ResourceId] = []
  let selected : Array[Bool] = []
  for _ in result {
    selected.push(false)
  }
  for _ in result {
    let mut best : Int? = None
    for index, candidate in result {
      if !selected[index] {
        match best {
          None => best = Some(index)
          Some(previous) =>
            if resource_key(candidate) < resource_key(result[previous]) {
              best = Some(index)
            }
        }
      }
    }
    match best {
      Some(index) => {
        selected[index] = true
        ordered.push(result[index])
      }
      None => ()
    }
  }
  ordered
}

///|
/// Explains actions without exposing version/configuration values. Callers
/// should validate the plan before presenting these explanations as executable.
pub fn explain_change_plan(
  plan : BatchedPlan,
  desired : Array[DesiredState],
  snapshot : ObservationSnapshot,
  dependencies : Array[(ResourceId, ResourceId)],
  policy : SafetyPolicy,
) -> PlanExplanation raise ModelError {
  validate_plan_freshness(plan.plan, observed_generation=snapshot.generation)
  let actions : Array[ActionExplanation] = []
  for operation in plan.plan.operations {
    let wanted = match explanation_find_desired(desired, operation.resource) {
      Some(value) => value
      None => raise ModelError::PlanMismatch("operation lacks desired state")
    }
    let observed = find_observation(snapshot.states, operation.resource)
    if observed is None &&
      validation_count_absent(snapshot.absent, operation.resource) != 1 {
      raise ModelError::StaleObservation("operation has unknown resource state")
    }
    let evaluation = evaluate_operation_safety(operation, policy)
    actions.push({
      operation,
      changed_fields: explanation_state_fields(wanted, observed),
      predecessors: explanation_predecessors(operation.resource, dependencies),
      snapshot_generation: snapshot.generation,
      policy_decision: evaluation.decision,
      risk: evaluation.risk,
      policy_reason: evaluation.reason_code,
    })
  }
  { plan_id: plan.plan.id, snapshot_generation: snapshot.generation, actions, }
}

///|
fn explanation_find_operation(
  operations : Array[Operation],
  resource : ResourceId,
) -> (Operation, Int)? {
  for index, operation in operations {
    if operation.resource == resource {
      return Some((operation, index))
    }
  }
  None
}

///|
/// Compares two plans for the same resource universe. An order change means
/// a shared resource moved to a different zero-based operation index.
pub fn compare_change_plans(
  before : Plan,
  after : Plan,
  policy : SafetyPolicy,
) -> PlanComparison raise ModelError {
  validate_unique_operations(before.operations)
  validate_unique_operations(after.operations)
  let added : Array[Operation] = []
  let removed : Array[Operation] = []
  let modified : Array[ModifiedAction] = []
  let reordered : Array[OrderChange] = []
  let risk_changed : Array[RiskChange] = []
  for old in before.operations {
    if explanation_find_operation(after.operations, old.resource) is None {
      removed.push(old)
    }
  }
  for new_index, current in after.operations {
    match explanation_find_operation(before.operations, current.resource) {
      None => added.push(current)
      Some((old, old_index)) => {
        if old != current {
          modified.push({
            resource: current.resource,
            before: old,
            after: current,
          })
        }
        if old_index != new_index {
          reordered.push({
            resource: current.resource,
            before_index: old_index,
            after_index: new_index,
          })
        }
        let old_risk = evaluate_operation_safety(old, policy).risk
        let new_risk = evaluate_operation_safety(current, policy).risk
        if old_risk != new_risk {
          risk_changed.push({
            resource: current.resource,
            before: old_risk,
            after: new_risk,
          })
        }
      }
    }
  }
  {
    added,
    removed,
    modified,
    reordered,
    risk_changed,
    before_generation: before.baseline_generation,
    after_generation: after.baseline_generation,
  }
}

///|
fn explanation_resource_json(resource : ResourceId) -> Json {
  Json::object(
    Map([
      ("kind", Json::string(resource.kind)),
      ("name", Json::string(resource.name)),
    ]),
  )
}

///|
fn explanation_action_name(action : ActionKind) -> String {
  match action {
    ActionKind::Create => "create"
    ActionKind::Update => "update"
    ActionKind::Scale => "scale"
    ActionKind::Restart => "restart"
    ActionKind::Delete => "delete"
    ActionKind::Unknown => "unknown"
  }
}

///|
fn explanation_risk_name(risk : RiskLevel) -> String {
  match risk {
    RiskLevel::Low => "low"
    RiskLevel::Medium => "medium"
    RiskLevel::High => "high"
    RiskLevel::Unknown => "unknown"
  }
}

///|
fn explanation_decision_name(decision : PolicyDecision) -> String {
  match decision {
    PolicyDecision::Allow => "allow"
    PolicyDecision::Deny => "deny"
    PolicyDecision::RequireApproval => "require_approval"
  }
}

///|
fn explanation_policy_reason_name(reason : PolicyReasonCode) -> String {
  match reason {
    PolicyReasonCode::LowRisk => "low_risk"
    PolicyReasonCode::MediumRisk => "medium_risk"
    PolicyReasonCode::HighRiskAction => "high_risk_action"
    PolicyReasonCode::DeleteProtection => "delete_protection"
    PolicyReasonCode::BatchRestart => "batch_restart"
    PolicyReasonCode::CriticalResource => "critical_resource"
    PolicyReasonCode::BudgetConflict => "budget_conflict"
    PolicyReasonCode::UnknownAction => "unknown_action"
  }
}

///|
fn explanation_operation_json(operation : Operation) -> Json {
  Json::object(
    Map([
      ("resource", explanation_resource_json(operation.resource)),
      ("action", Json::string(explanation_action_name(operation.action))),
      ("reason", Json::string(operation.reason)),
    ]),
  )
}

///|
pub fn ActionExplanation::to_json(self : ActionExplanation) -> Json {
  let fields : Array[Json] = []
  for field in self.changed_fields {
    fields.push(Json::string(field))
  }
  let predecessors : Array[Json] = []
  for resource in self.predecessors {
    predecessors.push(explanation_resource_json(resource))
  }
  Json::object(
    Map([
      ("operation", explanation_operation_json(self.operation)),
      ("changed_fields", Json::array(fields)),
      ("predecessors", Json::array(predecessors)),
      (
        "snapshot_generation",
        Json::number(self.snapshot_generation.to_double()),
      ),
      (
        "policy_decision",
        Json::string(explanation_decision_name(self.policy_decision)),
      ),
      (
        "policy_reason",
        Json::string(explanation_policy_reason_name(self.policy_reason)),
      ),
      ("risk", Json::string(explanation_risk_name(self.risk))),
    ]),
  )
}

///|
pub fn PlanExplanation::to_json(self : PlanExplanation) -> Json {
  let actions : Array[Json] = []
  for action in self.actions {
    actions.push(action.to_json())
  }
  Json::object(
    Map([
      ("plan_id", Json::string(self.plan_id.value)),
      (
        "snapshot_generation",
        Json::number(self.snapshot_generation.to_double()),
      ),
      ("actions", Json::array(actions)),
    ]),
  )
}

///|
pub fn PlanComparison::to_json(self : PlanComparison) -> Json {
  let added : Array[Json] = []
  let removed : Array[Json] = []
  let modified : Array[Json] = []
  let reordered : Array[Json] = []
  let risks : Array[Json] = []
  for operation in self.added {
    added.push(explanation_operation_json(operation))
  }
  for operation in self.removed {
    removed.push(explanation_operation_json(operation))
  }
  for change in self.modified {
    modified.push(
      Json::object(
        Map([
          ("resource", explanation_resource_json(change.resource)),
          ("before", explanation_operation_json(change.before)),
          ("after", explanation_operation_json(change.after)),
        ]),
      ),
    )
  }
  for change in self.reordered {
    reordered.push(
      Json::object(
        Map([
          ("resource", explanation_resource_json(change.resource)),
          ("before_index", Json::number(change.before_index.to_double())),
          ("after_index", Json::number(change.after_index.to_double())),
        ]),
      ),
    )
  }
  for change in self.risk_changed {
    risks.push(
      Json::object(
        Map([
          ("resource", explanation_resource_json(change.resource)),
          ("before", Json::string(explanation_risk_name(change.before))),
          ("after", Json::string(explanation_risk_name(change.after))),
        ]),
      ),
    )
  }
  Json::object(
    Map([
      ("added", Json::array(added)),
      ("removed", Json::array(removed)),
      ("modified", Json::array(modified)),
      ("reordered", Json::array(reordered)),
      ("risk_changed", Json::array(risks)),
      ("before_generation", Json::number(self.before_generation.to_double())),
      ("after_generation", Json::number(self.after_generation.to_double())),
    ]),
  )
}

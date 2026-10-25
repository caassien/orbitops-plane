///|
/// The caller attests that all entries were observed in one snapshot.
/// `absent` explicitly distinguishes a missing resource from an unknown one.
pub(all) struct ObservationSnapshot {
  generation : Int
  states : Array[ObservedState]
  absent : Array[ResourceId]
} derive(Debug, Eq)

///|
pub(all) enum ValidationStatus {
  Valid
  Invalid
  Stale
} derive(Debug, Eq)

///|
pub(all) enum ValidationCode {
  InvalidSnapshot
  StaleSnapshot
  UnknownResource
  ConflictingObservation
  InvalidInput
  PlanMismatch
  DependencyOrder
  BatchConflict
  BudgetExceeded
  PolicyDenied
  ApprovalRequired
  InvalidFeedback
  DuplicateFeedback
  PredecessorIncomplete
  FailedOperation
} derive(Debug, Eq)

///|
pub(all) struct ValidationIssue {
  code : ValidationCode
  resource : ResourceId?
  action : ActionKind?
  risk : RiskLevel
  explanation : String
} derive(Debug, Eq)

///|
pub(all) struct ValidationResult {
  status : ValidationStatus
  issues : Array[ValidationIssue]
  risk : RiskLevel
} derive(Debug, Eq)

///|
/// Validate one dispatch point. `dispatch_index` is the next operation in the
/// flattened plan; preceding operations must have successful feedback.
pub(all) struct PlanValidationInput {
  plan : BatchedPlan
  desired : Array[DesiredState]
  snapshot : ObservationSnapshot
  dependencies : Array[(ResourceId, ResourceId)]
  budget : ChangeBudget
  policy : SafetyPolicy
  approval : ApprovalState
  feedback : Array[ExecutionResult]
  dispatch_index : Int
} derive(Debug, Eq)

///|
fn validation_issue(
  issues : Array[ValidationIssue],
  code : ValidationCode,
  resource : ResourceId?,
  action : ActionKind?,
  risk : RiskLevel,
  explanation : String,
) -> Unit {
  issues.push({ code, resource, action, risk, explanation, })
}

///|
fn validation_risk_rank(risk : RiskLevel) -> Int {
  match risk {
    RiskLevel::Low => 0
    RiskLevel::Medium => 1
    RiskLevel::High => 2
    RiskLevel::Unknown => 3
  }
}

///|
fn validation_max_risk(left : RiskLevel, right : RiskLevel) -> RiskLevel {
  if validation_risk_rank(left) < validation_risk_rank(right) {
    right
  } else {
    left
  }
}

///|
fn validation_has_state(
  states : Array[ObservedState],
  resource : ResourceId,
) -> Bool {
  for state in states {
    if state.resource == resource {
      return true
    }
  }
  false
}

///|
fn validation_count_absent(
  absent : Array[ResourceId],
  resource : ResourceId,
) -> Int {
  let mut count = 0
  for missing in absent {
    if missing == resource {
      count += 1
    }
  }
  count
}

///|
fn validation_same_batches(
  left : Array[ChangeBatch],
  right : Array[ChangeBatch],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index in 0..<left.length() {
    if left[index].operations != right[index].operations {
      return false
    }
  }
  true
}

///|
fn validation_feedback_succeeded(
  feedback : Array[ExecutionResult],
  operation : Operation,
) -> Bool {
  for result in feedback {
    if result.operation == operation &&
      result.state == ExecutionState::Succeeded {
      return true
    }
  }
  false
}

///|
/// Checks a complete resource plan without executing it. Violations are
/// returned as data, so a host may show all relevant failures before dispatch.
/// Any snapshot generation change, including an unrelated resource change,
/// conservatively makes the plan stale.
pub fn validate_change_plan(input : PlanValidationInput) -> ValidationResult {
  let issues : Array[ValidationIssue] = []
  let mut risk = RiskLevel::Low
  let mut stale = false
  let plan = input.plan.plan
  if input.snapshot.generation <= 0 {
    validation_issue(
      issues,
      ValidationCode::InvalidSnapshot,
      None,
      None,
      RiskLevel::Unknown,
      "snapshot generation must be positive",
    )
  } else if input.snapshot.generation != plan.baseline_generation {
    stale = true
    validation_issue(
      issues,
      ValidationCode::StaleSnapshot,
      None,
      None,
      RiskLevel::Unknown,
      "snapshot generation differs from the plan baseline; replan even if the change seems unrelated",
    )
  }
  for desired in input.desired {
    let present = validation_has_state(input.snapshot.states, desired.resource)
    let absent_count = validation_count_absent(
      input.snapshot.absent,
      desired.resource,
    )
    if !present && absent_count == 0 {
      validation_issue(
        issues,
        ValidationCode::UnknownResource,
        Some(desired.resource),
        None,
        RiskLevel::Unknown,
        "resource is neither observed nor explicitly absent",
      )
    } else if (present && absent_count > 0) || absent_count > 1 {
      validation_issue(
        issues,
        ValidationCode::ConflictingObservation,
        Some(desired.resource),
        None,
        RiskLevel::Unknown,
        "resource observation conflicts with absence",
      )
    }
  }
  try {
    validate_unique_states(input.desired, input.snapshot.states)
    let expected = build_resource_plan(
      id=plan.id,
      desired=input.desired,
      observed=input.snapshot.states,
      dependencies=input.dependencies,
      baseline_generation=plan.baseline_generation,
      budget=input.budget,
    )
    if expected.plan.operations != plan.operations {
      validation_issue(
        issues,
        ValidationCode::PlanMismatch,
        None,
        None,
        RiskLevel::Unknown,
        "operations differ from the current desired/observed state",
      )
    }
    if !validation_same_batches(input.plan.batches, expected.batches) {
      validation_issue(
        issues,
        ValidationCode::BatchConflict,
        None,
        None,
        RiskLevel::High,
        "batch membership or dependency order differs from the safe plan",
      )
    }
  } catch {
    _ =>
      validation_issue(
        issues,
        ValidationCode::InvalidInput,
        None,
        None,
        RiskLevel::Unknown,
        "resource, dependency or budget input cannot form a valid plan",
      )
  }
  let flattened : Array[Operation] = []
  for batch in input.plan.batches {
    if batch.operations.length() > input.budget.max_parallel ||
      affected_resource_count(batch.operations) >
      input.budget.max_affected_resources {
      validation_issue(
        issues,
        ValidationCode::BudgetExceeded,
        None,
        None,
        RiskLevel::High,
        "batch exceeds parallel or affected-resource budget",
      )
    }
    for operation in batch.operations {
      flattened.push(operation)
    }
    try {
      let evaluation = evaluate_safety_policy(batch, input.policy)
      risk = validation_max_risk(risk, evaluation.risk)
      match evaluation.decision {
        PolicyDecision::Deny =>
          validation_issue(
            issues,
            ValidationCode::PolicyDenied,
            None,
            None,
            evaluation.risk,
            evaluation.explanation,
          )
        PolicyDecision::RequireApproval =>
          if input.approval != ApprovalState::Approved {
            validation_issue(
              issues,
              ValidationCode::ApprovalRequired,
              None,
              None,
              evaluation.risk,
              evaluation.explanation,
            )
          }
        PolicyDecision::Allow => ()
      }
    } catch {
      _ =>
        validation_issue(
          issues,
          ValidationCode::InvalidInput,
          None,
          None,
          RiskLevel::Unknown,
          "safety policy has invalid limits",
        )
    }
  }
  if flattened != plan.operations {
    validation_issue(
      issues,
      ValidationCode::DependencyOrder,
      None,
      None,
      RiskLevel::High,
      "flattened batch order differs from planned operation order",
    )
  }
  if input.approval == ApprovalState::Rejected {
    validation_issue(
      issues,
      ValidationCode::PolicyDenied,
      None,
      None,
      RiskLevel::High,
      "plan approval was rejected",
    )
  }
  if input.dispatch_index < 0 || input.dispatch_index > plan.operations.length() {
    validation_issue(
      issues,
      ValidationCode::InvalidFeedback,
      None,
      None,
      RiskLevel::Unknown,
      "dispatch index is outside the plan",
    )
  }
  for index, feedback in input.feedback {
    if feedback.plan_id != plan.id ||
      index >= plan.operations.length() ||
      feedback.operation != plan.operations[index] {
      validation_issue(
        issues,
        ValidationCode::InvalidFeedback,
        Some(feedback.operation.resource),
        Some(feedback.operation.action),
        RiskLevel::Unknown,
        "feedback must match the active plan and operation order",
      )
    }
    for prior in 0..<index {
      if input.feedback[prior].operation == feedback.operation {
        validation_issue(
          issues,
          ValidationCode::DuplicateFeedback,
          Some(feedback.operation.resource),
          Some(feedback.operation.action),
          RiskLevel::High,
          "operation has duplicate feedback",
        )
        break
      }
    }
    if feedback.state != ExecutionState::Succeeded {
      validation_issue(
        issues,
        ValidationCode::FailedOperation,
        Some(feedback.operation.resource),
        Some(feedback.operation.action),
        RiskLevel::High,
        "failed or skipped operation requires a new plan",
      )
    }
  }
  if input.dispatch_index >= 0 &&
    input.dispatch_index <= plan.operations.length() {
    if input.feedback.length() != input.dispatch_index {
      validation_issue(
        issues,
        ValidationCode::PredecessorIncomplete,
        None,
        None,
        RiskLevel::High,
        "all preceding operations need successful feedback",
      )
    }
    if input.dispatch_index < plan.operations.length() {
      let candidate = plan.operations[input.dispatch_index]
      for prior in 0..<input.dispatch_index {
        if dependency_path_exists(
            plan.operations[prior].resource,
            candidate.resource,
            input.dependencies,
            only_deletes(plan.operations),
          ) &&
          !validation_feedback_succeeded(input.feedback, plan.operations[prior]) {
          validation_issue(
            issues,
            ValidationCode::PredecessorIncomplete,
            Some(candidate.resource),
            Some(candidate.action),
            RiskLevel::High,
            "dependent operation cannot run before its predecessor succeeds",
          )
        }
      }
    }
  }
  for issue in issues {
    risk = validation_max_risk(risk, issue.risk)
  }
  let status = if stale {
    ValidationStatus::Stale
  } else if issues.length() > 0 {
    ValidationStatus::Invalid
  } else {
    ValidationStatus::Valid
  }
  { status, issues, risk, }
}

///|
fn validation_status_name(status : ValidationStatus) -> String {
  match status {
    ValidationStatus::Valid => "valid"
    ValidationStatus::Invalid => "invalid"
    ValidationStatus::Stale => "stale"
  }
}

///|
fn validation_code_name(code : ValidationCode) -> String {
  match code {
    ValidationCode::InvalidSnapshot => "invalid_snapshot"
    ValidationCode::StaleSnapshot => "stale_snapshot"
    ValidationCode::UnknownResource => "unknown_resource"
    ValidationCode::ConflictingObservation => "conflicting_observation"
    ValidationCode::InvalidInput => "invalid_input"
    ValidationCode::PlanMismatch => "plan_mismatch"
    ValidationCode::DependencyOrder => "dependency_order"
    ValidationCode::BatchConflict => "batch_conflict"
    ValidationCode::BudgetExceeded => "budget_exceeded"
    ValidationCode::PolicyDenied => "policy_denied"
    ValidationCode::ApprovalRequired => "approval_required"
    ValidationCode::InvalidFeedback => "invalid_feedback"
    ValidationCode::DuplicateFeedback => "duplicate_feedback"
    ValidationCode::PredecessorIncomplete => "predecessor_incomplete"
    ValidationCode::FailedOperation => "failed_operation"
  }
}

///|
pub fn ValidationIssue::to_json(self : ValidationIssue) -> Json {
  let resource = match self.resource {
    Some(value) => explanation_resource_json(value)
    None => Json::null()
  }
  let action = match self.action {
    Some(value) => Json::string(explanation_action_name(value))
    None => Json::null()
  }
  Json::object(
    Map([
      ("code", Json::string(validation_code_name(self.code))),
      ("resource", resource),
      ("action", action),
      ("risk", Json::string(explanation_risk_name(self.risk))),
      ("explanation", Json::string(self.explanation)),
    ]),
  )
}

///|
pub fn ValidationResult::to_json(self : ValidationResult) -> Json {
  let issues : Array[Json] = []
  for issue in self.issues {
    issues.push(issue.to_json())
  }
  Json::object(
    Map([
      ("status", Json::string(validation_status_name(self.status))),
      ("risk", Json::string(explanation_risk_name(self.risk))),
      ("issues", Json::array(issues)),
    ]),
  )
}

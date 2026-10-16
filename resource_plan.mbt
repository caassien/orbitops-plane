///|
fn find_observation(
  observed : Array[ObservedState],
  resource : ResourceId,
) -> ObservedState? {
  for state in observed {
    if state.resource == resource {
      return Some(state)
    }
  }
  None
}

///|
fn validate_unique_states(
  desired : Array[DesiredState],
  observed : Array[ObservedState],
) -> Unit raise ModelError {
  let desired_resources : Array[ResourceId] = []
  for state in desired {
    if contains_resource_id(desired_resources, state.resource) {
      raise ModelError::DuplicateResource(resource_key(state.resource))
    }
    desired_resources.push(state.resource)
  }
  let observed_resources : Array[ResourceId] = []
  for state in observed {
    if contains_resource_id(observed_resources, state.resource) {
      raise ModelError::DuplicateResource(resource_key(state.resource))
    }
    observed_resources.push(state.resource)
  }
}

///|
/// Compiles a complete desired set and one coherent observation snapshot into
/// a deterministic plan. Observed resources absent from the desired set are
/// unmanaged and are never deleted implicitly. Dependency endpoints must be
/// present in the desired set, even if they need no operation.
pub fn build_resource_plan(
  id~ : PlanId,
  desired~ : Array[DesiredState],
  observed~ : Array[ObservedState],
  dependencies~ : Array[(ResourceId, ResourceId)],
  baseline_generation~ : Int,
  budget~ : ChangeBudget,
) -> BatchedPlan raise ModelError {
  if baseline_generation <= 0 {
    raise ModelError::NonPositiveGeneration
  }
  validate_unique_states(desired, observed)
  let resources : Array[ResourceId] = []
  for state in desired {
    resources.push(state.resource)
  }
  validate_resource_dependencies(resources, dependencies)
  let operations : Array[Operation] = []
  for state in desired {
    match compute_diff(state, find_observation(observed, state.resource)) {
      DiffResult::Action(operation) => operations.push(operation)
      DiffResult::NoChange => ()
    }
  }
  let plan = build_ordered_plan(
    id~,
    operations~,
    dependencies~,
    baseline_generation~,
  )
  batch_plan_with_dependencies(plan, budget, dependencies)
}

///|
/// Returns the next action only while the observation still matches the plan
/// baseline. Call before each dispatch, not just at the start of execution.
pub fn next_reconciliation_operation(
  reconciliation : Reconciliation,
  observed_generation~ : Int,
) -> Operation raise ModelError {
  if reconciliation.state != ReconciliationState::Executing {
    raise ModelError::InvalidTransition("run is not executing")
  }
  validate_plan_freshness(reconciliation.plan.plan, observed_generation~)
  match
    controller_operation_at(reconciliation.plan, reconciliation.next_operation) {
    Some(operation) => operation
    None => raise ModelError::InvalidTransition("no operation awaits dispatch")
  }
}

///|
/// Replans after feedback from a newer complete observation snapshot. The new
/// snapshot, not a prior success receipt, determines which resources remain
/// different. A fresh plan ID and policy evaluation are required for execution.
pub fn replan_remaining(
  reconciliation : Reconciliation,
  id~ : PlanId,
  desired~ : Array[DesiredState],
  observed~ : Array[ObservedState],
  dependencies~ : Array[(ResourceId, ResourceId)],
  observed_generation~ : Int,
  budget~ : ChangeBudget,
) -> BatchedPlan raise ModelError {
  if reconciliation.state != ReconciliationState::Executing &&
    reconciliation.state != ReconciliationState::Failed {
    raise ModelError::InvalidTransition("run has no unfinished execution")
  }
  if reconciliation.results.length() == 0 {
    raise ModelError::InvalidTransition("no execution feedback to replan")
  }
  if id == reconciliation.plan.plan.id {
    raise ModelError::PlanMismatch("replan requires a new plan ID")
  }
  if observed_generation <= reconciliation.plan.plan.baseline_generation {
    raise ModelError::StaleObservation("replan requires a newer observation")
  }
  build_resource_plan(
    id~,
    desired~,
    observed~,
    dependencies~,
    baseline_generation=observed_generation,
    budget~,
  )
}

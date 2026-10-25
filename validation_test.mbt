///|
fn validation_fixture() -> @orbitops_plane.PlanValidationInput raise @orbitops_plane.ModelError {
  let database = @orbitops_plane.ResourceId::new(
    kind="database",
    name="primary",
  )
  let api = @orbitops_plane.ResourceId::new(kind="service", name="api")
  let old = @orbitops_plane.ResourceSpec::new(
    version="v1",
    replicas=1,
    config_fingerprint="old",
    enabled=true,
  )
  let new = @orbitops_plane.ResourceSpec::new(
    version="v2",
    replicas=1,
    config_fingerprint="new",
    enabled=true,
  )
  let desired = [
    @orbitops_plane.DesiredState::new(resource=api, spec=new, generation=2),
    @orbitops_plane.DesiredState::new(resource=database, spec=new, generation=2),
  ]
  let observed = [
    @orbitops_plane.ObservedState::new(
      resource=database,
      spec=old,
      generation=1,
      healthy=true,
    ),
    @orbitops_plane.ObservedState::new(
      resource=api,
      spec=old,
      generation=1,
      healthy=true,
    ),
  ]
  let dependencies = [(database, api)]
  let budget = @orbitops_plane.ChangeBudget::new(
    max_parallel=2,
    max_affected_resources=2,
    isolate_high_risk=false,
  )
  let plan = @orbitops_plane.build_resource_plan(
    id=@orbitops_plane.PlanId::new(value="validation-plan"),
    desired~,
    observed~,
    dependencies~,
    baseline_generation=1,
    budget~,
  )
  {
    plan,
    desired,
    snapshot: { generation: 1, states: observed, absent: [], },
    dependencies,
    budget,
    policy: @orbitops_plane.SafetyPolicy::new(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
    approval: @orbitops_plane.ApprovalState::NotRequired,
    feedback: [],
    dispatch_index: 0,
  }
}

///|
fn validate_fixture(
  input : @orbitops_plane.PlanValidationInput,
  snapshot : @orbitops_plane.ObservationSnapshot,
  feedback : Array[@orbitops_plane.ExecutionResult],
  dispatch_index : Int,
  approval : @orbitops_plane.ApprovalState,
) -> @orbitops_plane.ValidationResult {
  @orbitops_plane.validate_change_plan({
    plan: input.plan,
    desired: input.desired,
    snapshot,
    dependencies: input.dependencies,
    budget: input.budget,
    policy: input.policy,
    approval,
    feedback,
    dispatch_index,
  })
}

///|
fn has_validation_code(
  result : @orbitops_plane.ValidationResult,
  code : @orbitops_plane.ValidationCode,
) -> Bool {
  for issue in result.issues {
    if issue.code == code {
      return true
    }
  }
  false
}

///|
test "independent plan validation accepts a complete snapshot" {
  let input = try! validation_fixture()
  let result = @orbitops_plane.validate_change_plan(input)
  assert_eq(result.status, @orbitops_plane.ValidationStatus::Valid)
  assert_eq(result.issues.length(), 0)
}

///|
test "a global snapshot change is stale even if unrelated" {
  let input = try! validation_fixture()
  let snapshot : @orbitops_plane.ObservationSnapshot = {
    generation: 2,
    states: input.snapshot.states,
    absent: [],
  }
  let result = validate_fixture(
    input,
    snapshot,
    [],
    0,
    @orbitops_plane.ApprovalState::NotRequired,
  )
  assert_eq(result.status, @orbitops_plane.ValidationStatus::Stale)
  assert_true(
    has_validation_code(result, @orbitops_plane.ValidationCode::StaleSnapshot),
  )
  let serialized = result.to_json().stringify()
  assert_true(serialized.contains("\"status\":\"stale\""))
  assert_true(serialized.contains("\"code\":\"stale_snapshot\""))
}

///|
test "unknown resource state cannot be treated as an absent resource" {
  let input = try! validation_fixture()
  let snapshot : @orbitops_plane.ObservationSnapshot = {
    generation: 1,
    states: [input.snapshot.states[0]],
    absent: [],
  }
  let result = validate_fixture(
    input,
    snapshot,
    [],
    0,
    @orbitops_plane.ApprovalState::NotRequired,
  )
  assert_eq(result.status, @orbitops_plane.ValidationStatus::Invalid)
  assert_true(
    has_validation_code(result, @orbitops_plane.ValidationCode::UnknownResource),
  )
}

///|
test "a dependent action needs predecessor feedback" {
  let input = try! validation_fixture()
  let missing = validate_fixture(
    input,
    input.snapshot,
    [],
    1,
    @orbitops_plane.ApprovalState::NotRequired,
  )
  assert_eq(missing.status, @orbitops_plane.ValidationStatus::Invalid)
  assert_true(
    has_validation_code(
      missing,
      @orbitops_plane.ValidationCode::PredecessorIncomplete,
    ),
  )
  let success = try! @orbitops_plane.ExecutionResult::new(
    plan_id=input.plan.plan.id,
    operation=input.plan.plan.operations[0],
    state=@orbitops_plane.ExecutionState::Succeeded,
    message="database ready",
  )
  let valid = validate_fixture(
    input,
    input.snapshot,
    [success],
    1,
    @orbitops_plane.ApprovalState::NotRequired,
  )
  assert_eq(valid.status, @orbitops_plane.ValidationStatus::Valid)
}

///|
test "duplicate or failed feedback cannot authorize dispatch" {
  let input = try! validation_fixture()
  let operation = input.plan.plan.operations[0]
  let success = try! @orbitops_plane.ExecutionResult::new(
    plan_id=input.plan.plan.id,
    operation~,
    state=@orbitops_plane.ExecutionState::Succeeded,
    message="done",
  )
  let duplicate = validate_fixture(
    input,
    input.snapshot,
    [success, success],
    2,
    @orbitops_plane.ApprovalState::NotRequired,
  )
  assert_true(
    has_validation_code(
      duplicate,
      @orbitops_plane.ValidationCode::DuplicateFeedback,
    ),
  )
  let failed = try! @orbitops_plane.ExecutionResult::new(
    plan_id=input.plan.plan.id,
    operation~,
    state=@orbitops_plane.ExecutionState::Failed,
    message="failed",
  )
  let result = validate_fixture(
    input,
    input.snapshot,
    [failed],
    1,
    @orbitops_plane.ApprovalState::NotRequired,
  )
  assert_true(
    has_validation_code(result, @orbitops_plane.ValidationCode::FailedOperation),
  )
}

///|
test "input permutation leaves the validation result unchanged" {
  let input = try! validation_fixture()
  let permuted : @orbitops_plane.PlanValidationInput = {
    plan: input.plan,
    desired: [input.desired[1], input.desired[0]],
    snapshot: {
      generation: 1,
      states: [input.snapshot.states[1], input.snapshot.states[0]],
      absent: [],
    },
    dependencies: input.dependencies,
    budget: input.budget,
    policy: input.policy,
    approval: input.approval,
    feedback: input.feedback,
    dispatch_index: 0,
  }
  assert_eq(
    @orbitops_plane.validate_change_plan(permuted),
    @orbitops_plane.validate_change_plan(input),
  )
}

///|
test "batch tampering and approval requirement are independently reported" {
  let input = try! validation_fixture()
  let reversed : @orbitops_plane.BatchedPlan = {
    plan: input.plan.plan,
    batches: [
      { operations: [input.plan.plan.operations[1]], },
      { operations: [input.plan.plan.operations[0]], },
    ],
  }
  let tampered : @orbitops_plane.PlanValidationInput = {
    plan: reversed,
    desired: input.desired,
    snapshot: input.snapshot,
    dependencies: input.dependencies,
    budget: input.budget,
    policy: input.policy,
    approval: input.approval,
    feedback: [],
    dispatch_index: 0,
  }
  let result = @orbitops_plane.validate_change_plan(tampered)
  assert_true(
    has_validation_code(result, @orbitops_plane.ValidationCode::BatchConflict),
  )
  let guarded : @orbitops_plane.PlanValidationInput = {
    plan: input.plan,
    desired: input.desired,
    snapshot: input.snapshot,
    dependencies: input.dependencies,
    budget: input.budget,
    policy: try! @orbitops_plane.SafetyPolicy::new(
      critical_resources=[input.plan.plan.operations[0].resource],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
    approval: @orbitops_plane.ApprovalState::Pending,
    feedback: [],
    dispatch_index: 0,
  }
  let pending = @orbitops_plane.validate_change_plan(guarded)
  assert_true(
    has_validation_code(
      pending,
      @orbitops_plane.ValidationCode::ApprovalRequired,
    ),
  )
}

///|
test "an oversized dispatch batch reports a budget violation" {
  let input = try! validation_fixture()
  let tight_budget = try! @orbitops_plane.ChangeBudget::new(
    max_parallel=1,
    max_affected_resources=1,
    isolate_high_risk=false,
  )
  let combined : @orbitops_plane.BatchedPlan = {
    plan: input.plan.plan,
    batches: [{ operations: input.plan.plan.operations, }],
  }
  let request : @orbitops_plane.PlanValidationInput = {
    plan: combined,
    desired: input.desired,
    snapshot: input.snapshot,
    dependencies: input.dependencies,
    budget: tight_budget,
    policy: input.policy,
    approval: input.approval,
    feedback: [],
    dispatch_index: 0,
  }
  let result = @orbitops_plane.validate_change_plan(request)
  assert_eq(result.status, @orbitops_plane.ValidationStatus::Invalid)
  assert_true(
    has_validation_code(result, @orbitops_plane.ValidationCode::BudgetExceeded),
  )
  assert_true(
    has_validation_code(result, @orbitops_plane.ValidationCode::BatchConflict),
  )
}

///|
test "an explicitly absent resource can be planned for creation" {
  let input = try! validation_fixture()
  let observed = [input.snapshot.states[0]]
  let missing = input.desired[0].resource
  let plan = try! @orbitops_plane.build_resource_plan(
    id=input.plan.plan.id,
    desired=input.desired,
    observed~,
    dependencies=input.dependencies,
    baseline_generation=1,
    budget=input.budget,
  )
  let request : @orbitops_plane.PlanValidationInput = {
    plan,
    desired: input.desired,
    snapshot: { generation: 1, states: observed, absent: [missing], },
    dependencies: input.dependencies,
    budget: input.budget,
    policy: input.policy,
    approval: input.approval,
    feedback: [],
    dispatch_index: 0,
  }
  let result = @orbitops_plane.validate_change_plan(request)
  assert_eq(result.status, @orbitops_plane.ValidationStatus::Valid)
  assert_eq(plan.plan.operations[1].action, @orbitops_plane.ActionKind::Create)
}

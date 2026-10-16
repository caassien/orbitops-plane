///|
fn scenario_resource(
  kind : String,
  name : String,
) -> @orbitops_plane.ResourceId raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceId::new(kind~, name~)
}

///|
fn scenario_spec(
  version : String,
  replicas : Int,
  config : String,
) -> @orbitops_plane.ResourceSpec raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceSpec::new(
    version~,
    replicas~,
    config_fingerprint=config,
    enabled=true,
  )
}

///|
fn scenario_desired(
  resource : @orbitops_plane.ResourceId,
  spec : @orbitops_plane.ResourceSpec,
) -> @orbitops_plane.DesiredState raise @orbitops_plane.ModelError {
  @orbitops_plane.DesiredState::new(resource~, spec~, generation=2)
}

///|
fn scenario_observed(
  resource : @orbitops_plane.ResourceId,
  spec : @orbitops_plane.ResourceSpec,
) -> @orbitops_plane.ObservedState raise @orbitops_plane.ModelError {
  @orbitops_plane.ObservedState::new(
    resource~,
    spec~,
    generation=1,
    healthy=true,
  )
}

///|
fn scenario_budget() -> @orbitops_plane.ChangeBudget raise @orbitops_plane.ModelError {
  @orbitops_plane.ChangeBudget::new(
    max_parallel=2,
    max_affected_resources=2,
    isolate_high_risk=false,
  )
}

///|
test "resource snapshot compiles dependent changes and replans after feedback" {
  let database = try! scenario_resource("database", "primary")
  let api = try! scenario_resource("service", "api")
  let worker = try! scenario_resource("worker", "jobs")
  let database_v1 = try! scenario_spec("v1", 1, "db-v1")
  let database_v2 = try! scenario_spec("v1", 1, "db-v2")
  let api_v1 = try! scenario_spec("v1", 2, "api")
  let api_v2 = try! scenario_spec("v2", 2, "api")
  let worker_v1 = try! scenario_spec("v1", 2, "worker")
  let worker_v2 = try! scenario_spec("v1", 4, "worker")
  let desired = [
    try! scenario_desired(worker, worker_v2),
    try! scenario_desired(api, api_v2),
    try! scenario_desired(database, database_v2),
  ]
  let observed = [
    try! scenario_observed(api, api_v1),
    try! scenario_observed(database, database_v1),
    try! scenario_observed(worker, worker_v1),
  ]
  let dependencies = [(database, api), (api, worker)]
  let id = try! @orbitops_plane.PlanId::new(value="snapshot-1")
  let plan = try! @orbitops_plane.build_resource_plan(
    id~,
    desired~,
    observed~,
    dependencies~,
    baseline_generation=1,
    budget=try! scenario_budget(),
  )
  assert_eq(plan.plan.operations.length(), 3)
  assert_eq(plan.batches.length(), 3)
  assert_eq(plan.plan.operations[0].resource, database)
  assert_eq(plan.plan.operations[0].action, @orbitops_plane.ActionKind::Update)
  assert_eq(plan.plan.operations[1].resource, api)
  assert_eq(plan.plan.operations[1].action, @orbitops_plane.ActionKind::Update)
  assert_eq(plan.plan.operations[2].resource, worker)
  assert_eq(plan.plan.operations[2].action, @orbitops_plane.ActionKind::Scale)
  for batch in plan.batches {
    assert_eq(batch.operations.length(), 1)
  }
  let started = try! @orbitops_plane.start_reconciliation(
    plan,
    observed_generation=1,
  )
  let ready = try! @orbitops_plane.evaluate_reconciliation(
    started,
    @orbitops_plane.SafetyPolicy::new(
      critical_resources=[],
      max_batch_operations=2,
      max_affected_resources=2,
    ),
  )
  let executing = try! @orbitops_plane.begin_execution(
    ready,
    observed_generation=1,
  )
  let first = try! @orbitops_plane.next_reconciliation_operation(
    executing,
    observed_generation=1,
  )
  assert_eq(first.resource, database)
  let with_feedback = try! @orbitops_plane.apply_execution_result(
    executing,
    try! @orbitops_plane.ExecutionResult::new(
      plan_id=id,
      operation=first,
      state=@orbitops_plane.ExecutionState::Succeeded,
      message="database updated",
    ),
  )
  try
    @orbitops_plane.next_reconciliation_operation(
      with_feedback,
      observed_generation=2,
    )
  catch {
    @orbitops_plane.ModelError::StalePlan(_) => ()
    _ => fail("wrong stale plan error")
  } noraise {
    _ => fail("old API operation was dispatched")
  }
  let next = try! @orbitops_plane.replan_remaining(
    with_feedback,
    id=try! @orbitops_plane.PlanId::new(value="snapshot-2"),
    desired~,
    observed=[
      try! scenario_observed(database, database_v2),
      try! scenario_observed(api, api_v1),
      try! scenario_observed(worker, worker_v1),
    ],
    dependencies~,
    observed_generation=2,
    budget=try! scenario_budget(),
  )
  assert_eq(next.plan.baseline_generation, 2)
  assert_eq(next.plan.operations.length(), 2)
  assert_eq(next.plan.operations[0].resource, api)
  assert_eq(next.plan.operations[1].resource, worker)
  assert_eq(next.batches.length(), 2)
}

///|
test "transitive dependency crosses batches through unchanged resource" {
  let database = try! scenario_resource("database", "primary")
  let api = try! scenario_resource("service", "api")
  let worker = try! scenario_resource("worker", "jobs")
  let stable = try! scenario_spec("v1", 1, "stable")
  let changed = try! scenario_spec("v2", 1, "stable")
  let plan = try! @orbitops_plane.build_resource_plan(
    id=try! @orbitops_plane.PlanId::new(value="transitive"),
    desired=[
      try! scenario_desired(worker, changed),
      try! scenario_desired(api, stable),
      try! scenario_desired(database, changed),
    ],
    observed=[
      try! scenario_observed(worker, stable),
      try! scenario_observed(api, stable),
      try! scenario_observed(database, stable),
    ],
    dependencies=[(database, api), (api, worker)],
    baseline_generation=1,
    budget=try! scenario_budget(),
  )
  assert_eq(plan.plan.operations.length(), 2)
  assert_eq(plan.plan.operations[0].resource, database)
  assert_eq(plan.plan.operations[1].resource, worker)
  assert_eq(plan.batches.length(), 2)
}

///|
test "independent changes share the available parallel budget" {
  let first = try! scenario_resource("service", "a")
  let second = try! scenario_resource("service", "b")
  let old = try! scenario_spec("v1", 1, "stable")
  let new = try! scenario_spec("v2", 1, "stable")
  let plan = try! @orbitops_plane.build_resource_plan(
    id=try! @orbitops_plane.PlanId::new(value="parallel"),
    desired=[
      try! scenario_desired(second, new),
      try! scenario_desired(first, new),
    ],
    observed=[
      try! scenario_observed(first, old),
      try! scenario_observed(second, old),
    ],
    dependencies=[],
    baseline_generation=1,
    budget=try! scenario_budget(),
  )
  assert_eq(plan.batches.length(), 1)
  assert_eq(plan.batches[0].operations.length(), 2)
  assert_eq(plan.plan.operations[0].resource, first)
}

///|
test "cross-resource drift only updates API then becomes a no-op" {
  let api = try! scenario_resource("service", "api")
  let database = try! scenario_resource("database", "primary")
  let worker = try! scenario_resource("worker", "jobs")
  let unmanaged = try! scenario_resource("service", "legacy")
  let spec = try! scenario_spec("v2", 2, "api-v2")
  let old = try! scenario_spec("v1", 2, "api-v1")
  let desired = [
    try! scenario_desired(database, spec),
    try! scenario_desired(api, spec),
    try! scenario_desired(worker, spec),
  ]
  let drift = try! @orbitops_plane.build_resource_plan(
    id=try! @orbitops_plane.PlanId::new(value="drift"),
    desired~,
    observed=[
      try! scenario_observed(api, old),
      try! scenario_observed(database, spec),
      try! scenario_observed(worker, spec),
    ],
    dependencies=[(database, api), (api, worker)],
    baseline_generation=1,
    budget=try! scenario_budget(),
  )
  assert_eq(drift.plan.operations.length(), 1)
  assert_eq(drift.plan.operations[0].resource, api)
  let converged = try! @orbitops_plane.build_resource_plan(
    id=try! @orbitops_plane.PlanId::new(value="no-drift"),
    desired~,
    observed=[
      try! scenario_observed(api, spec),
      try! scenario_observed(database, spec),
      try! scenario_observed(worker, spec),
      try! scenario_observed(unmanaged, spec),
    ],
    dependencies=[(database, api), (api, worker)],
    baseline_generation=2,
    budget=try! scenario_budget(),
  )
  assert_eq(converged.plan.operations.length(), 0)
  assert_eq(converged.batches.length(), 0)
}

///|
test "delete plan reverses a transitive dependency" {
  let database = try! scenario_resource("database", "primary")
  let api = try! scenario_resource("service", "api")
  let worker = try! scenario_resource("worker", "jobs")
  let enabled = try! scenario_spec("v1", 1, "stable")
  let disabled = try! @orbitops_plane.ResourceSpec::new(
    version="v1",
    replicas=1,
    config_fingerprint="stable",
    enabled=false,
  )
  let plan = try! @orbitops_plane.build_resource_plan(
    id=try! @orbitops_plane.PlanId::new(value="delete"),
    desired=[
      try! scenario_desired(database, disabled),
      try! scenario_desired(api, enabled),
      try! scenario_desired(worker, disabled),
    ],
    observed=[
      try! scenario_observed(database, enabled),
      try! scenario_observed(api, enabled),
      try! scenario_observed(worker, enabled),
    ],
    dependencies=[(database, api), (api, worker)],
    baseline_generation=1,
    budget=try! scenario_budget(),
  )
  assert_eq(plan.plan.operations[0].resource, worker)
  assert_eq(plan.plan.operations[1].resource, database)
  assert_eq(plan.batches.length(), 2)
}

///|
test "dependent operations in an unordered plan cannot be batched" {
  let database = try! scenario_resource("database", "primary")
  let api = try! scenario_resource("service", "api")
  let operations = [
    try! @orbitops_plane.Operation::new(
      resource=api,
      action=@orbitops_plane.ActionKind::Update,
      reason="api",
    ),
    try! @orbitops_plane.Operation::new(
      resource=database,
      action=@orbitops_plane.ActionKind::Update,
      reason="database",
    ),
  ]
  let plan = try! @orbitops_plane.Plan::new(
    id=try! @orbitops_plane.PlanId::new(value="unordered"),
    operations~,
    baseline_generation=1,
  )
  try
    @orbitops_plane.batch_plan_with_dependencies(plan, try! scenario_budget(), [
      (database, api),
    ])
  catch {
    @orbitops_plane.ModelError::InvalidDependency(_) => ()
    _ => fail("wrong unordered plan error")
  } noraise {
    _ => fail("expected dependency order validation")
  }
}

///|
test "duplicate desired resources are rejected" {
  let api = try! scenario_resource("service", "api")
  let spec = try! scenario_spec("v1", 1, "api")
  try
    @orbitops_plane.build_resource_plan(
      id=try! @orbitops_plane.PlanId::new(value="duplicate"),
      desired=[
        try! scenario_desired(api, spec),
        try! scenario_desired(api, spec),
      ],
      observed=[],
      dependencies=[],
      baseline_generation=1,
      budget=try! scenario_budget(),
    )
  catch {
    @orbitops_plane.ModelError::DuplicateResource(resource) =>
      assert_eq(resource, "service/api")
    _ => fail("wrong duplicate resource error")
  } noraise {
    _ => fail("expected a duplicate resource error")
  }
}

///|
test "plan explanations name state differences and dependencies without values" {
  let input = try! validation_fixture()
  let explained = try! @orbitops_plane.explain_change_plan(
    input.plan,
    input.desired,
    input.snapshot,
    input.dependencies,
    input.policy,
  )
  assert_eq(explained.actions.length(), 2)
  assert_eq(explained.actions[0].operation.resource.kind, "database")
  assert_eq(explained.actions[0].changed_fields, [
    "version", "config_fingerprint",
  ])
  assert_eq(explained.actions[1].predecessors.length(), 1)
  assert_eq(explained.actions[1].predecessors[0].kind, "database")
  assert_eq(explained.actions[1].snapshot_generation, 1)
  let serialized = explained.to_json().stringify()
  assert_true(serialized.contains("changed_fields"))
  assert_true(serialized.contains("policy_reason"))
  assert_true(!serialized.contains("\"old\""))
  assert_true(!serialized.contains("\"new\""))
}

///|
test "plan explanations reject an unknown observation and stale baseline" {
  let input = try! validation_fixture()
  let unknown : @orbitops_plane.ObservationSnapshot = {
    generation: 1,
    states: [input.snapshot.states[0]],
    absent: [],
  }
  try {
    ignore(
      @orbitops_plane.explain_change_plan(
        input.plan,
        input.desired,
        unknown,
        input.dependencies,
        input.policy,
      ),
    )
    fail("unknown resource should not be explained as observed")
  } catch {
    @orbitops_plane.ModelError::StaleObservation(_) => ()
    _ => fail("expected unknown observation error")
  }
  let newer : @orbitops_plane.ObservationSnapshot = {
    generation: 2,
    states: input.snapshot.states,
    absent: [],
  }
  try {
    ignore(
      @orbitops_plane.explain_change_plan(
        input.plan,
        input.desired,
        newer,
        input.dependencies,
        input.policy,
      ),
    )
    fail("newer snapshot should stale the explanation")
  } catch {
    @orbitops_plane.ModelError::StalePlan(_) => ()
    _ => fail("expected stale plan error")
  }
}

///|
test "plan comparison reports additions removals modifications and risk" {
  let input = try! validation_fixture()
  let api = input.plan.plan.operations[1]
  let worker = try! @orbitops_plane.ResourceId::new(kind="worker", name="jobs")
  let changed = try! @orbitops_plane.Operation::new(
    resource=api.resource,
    action=@orbitops_plane.ActionKind::Restart,
    reason="unhealthy",
  )
  let added = try! @orbitops_plane.Operation::new(
    resource=worker,
    action=@orbitops_plane.ActionKind::Create,
    reason="missing",
  )
  let after = try! @orbitops_plane.Plan::new(
    id=try! @orbitops_plane.PlanId::new(value="after"),
    operations=[changed, added],
    baseline_generation=2,
  )
  let compared = try! @orbitops_plane.compare_change_plans(
    input.plan.plan,
    after,
    input.policy,
  )
  assert_eq(compared.added, [added])
  assert_eq(compared.removed, [input.plan.plan.operations[0]])
  assert_eq(compared.modified.length(), 1)
  assert_eq(compared.reordered.length(), 1)
  assert_eq(compared.reordered[0].before_index, 1)
  assert_eq(compared.reordered[0].after_index, 0)
  assert_eq(compared.risk_changed.length(), 1)
  assert_eq(compared.risk_changed[0].before, @orbitops_plane.RiskLevel::Medium)
  assert_eq(compared.risk_changed[0].after, @orbitops_plane.RiskLevel::High)
  assert_eq(compared.before_generation, 1)
  assert_eq(compared.after_generation, 2)
  let serialized = compared.to_json().stringify()
  assert_true(serialized.contains("risk_changed"))
  assert_true(serialized.contains("before_generation"))
  let secret_reason = try! @orbitops_plane.Operation::new(
    resource=worker,
    action=@orbitops_plane.ActionKind::Create,
    reason="credential=private-value",
  )
  let secret_plan = try! @orbitops_plane.Plan::new(
    id=try! @orbitops_plane.PlanId::new(value="secret-plan"),
    operations=[secret_reason],
    baseline_generation=3,
  )
  let safe_comparison = try! @orbitops_plane.compare_change_plans(
    after,
    secret_plan,
    input.policy,
  )
  assert_true(!safe_comparison.to_json().stringify().contains("private-value"))
}

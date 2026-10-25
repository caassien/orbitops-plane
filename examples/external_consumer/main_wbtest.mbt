///|
test "independent consumer validates a dependency-aware service release" {
  let (plan, result) = try! service_release()
  assert_eq(plan.plan.operations.length(), 2)
  assert_eq(plan.batches.length(), 2)
  assert_eq(plan.plan.operations[0].resource.name, "database")
  assert_eq(result.status, @orbitops_plane.ValidationStatus::Valid)
}

///|
test "same public API validates a local configuration change" {
  let (plan, result) = try! local_configuration()
  assert_eq(plan.plan.operations.length(), 1)
  assert_eq(plan.plan.operations[0].resource.kind, "local-file")
  assert_eq(result.status, @orbitops_plane.ValidationStatus::Valid)
}

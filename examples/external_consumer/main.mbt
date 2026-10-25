///|
/// A consumer-owned facade over the same published OrbitOps planning and
/// validation APIs. No Kubernetes model or API is imported here.
fn verify_change(
  id : String,
  desired : Array[@orbitops_plane.DesiredState],
  observed : Array[@orbitops_plane.ObservedState],
  dependencies : Array[(@orbitops_plane.ResourceId, @orbitops_plane.ResourceId)],
  generation : Int,
) -> (@orbitops_plane.BatchedPlan, @orbitops_plane.ValidationResult) raise @orbitops_plane.ModelError {
  let budget = @orbitops_plane.ChangeBudget::new(
    max_parallel=2,
    max_affected_resources=2,
    isolate_high_risk=false,
  )
  let policy = @orbitops_plane.SafetyPolicy::new(
    critical_resources=[],
    max_batch_operations=2,
    max_affected_resources=2,
  )
  let plan = @orbitops_plane.build_resource_plan(
    id=@orbitops_plane.PlanId::new(value=id),
    desired~,
    observed~,
    dependencies~,
    baseline_generation=generation,
    budget~,
  )
  let result = @orbitops_plane.validate_change_plan({
    plan,
    desired,
    snapshot: { generation, states: observed, absent: [], },
    dependencies,
    budget,
    policy,
    approval: @orbitops_plane.ApprovalState::NotRequired,
    feedback: [],
    dispatch_index: 0,
  })
  (plan, result)
}

///|
fn spec(
  fingerprint : String,
) -> @orbitops_plane.ResourceSpec raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceSpec::new(
    version="1",
    replicas=1,
    config_fingerprint=fingerprint,
    enabled=true,
  )
}

///|
fn service_release() -> (
  @orbitops_plane.BatchedPlan,
  @orbitops_plane.ValidationResult,
) raise @orbitops_plane.ModelError {
  let database = @orbitops_plane.ResourceId::new(
    kind="service",
    name="database",
  )
  let api = @orbitops_plane.ResourceId::new(kind="service", name="api")
  let desired = [
    @orbitops_plane.DesiredState::new(
      resource=api,
      spec=spec("api-v2"),
      generation=2,
    ),
    @orbitops_plane.DesiredState::new(
      resource=database,
      spec=spec("schema-v2"),
      generation=2,
    ),
  ]
  let observed = [
    @orbitops_plane.ObservedState::new(
      resource=api,
      spec=spec("api-v1"),
      generation=1,
      healthy=true,
    ),
    @orbitops_plane.ObservedState::new(
      resource=database,
      spec=spec("schema-v1"),
      generation=1,
      healthy=true,
    ),
  ]
  verify_change("release", desired, observed, [(database, api)], 1)
}

///|
fn local_configuration() -> (
  @orbitops_plane.BatchedPlan,
  @orbitops_plane.ValidationResult,
) raise @orbitops_plane.ModelError {
  let file = @orbitops_plane.ResourceId::new(kind="local-file", name="app.conf")
  verify_change(
    "local-config",
    [
      @orbitops_plane.DesiredState::new(
        resource=file,
        spec=spec("sha256-new"),
        generation=2,
      ),
    ],
    [
      @orbitops_plane.ObservedState::new(
        resource=file,
        spec=spec("sha256-old"),
        generation=1,
        healthy=true,
      ),
    ],
    [],
    1,
  )
}

///|
fn main {
  try {
    let (release, release_result) = service_release()
    let (configuration, config_result) = local_configuration()
    println(
      "release_actions=\{release.plan.operations.length()} release_valid=\{release_result.status == @orbitops_plane.ValidationStatus::Valid}",
    )
    println(
      "config_actions=\{configuration.plan.operations.length()} config_valid=\{config_result.status == @orbitops_plane.ValidationStatus::Valid}",
    )
  } catch {
    _ => println("consumer example failed")
  }
}

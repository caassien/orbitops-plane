///|
/// KubeMoon owns the Kubernetes object; this adapter extracts only the fields
/// that OrbitOps can represent. Collection resourceVersion remains an opaque
/// host concern, so the host supplies a separate snapshot generation.
pub fn desired_from_configmap(
  object : @object.DynamicObject,
  desired_generation : Int,
) -> Result[@orbitops_plane.DesiredState, String] {
  guard object.namespace_name() is Some(namespace_name) else {
    return Err("ConfigMap must have a namespace")
  }
  let fingerprint = match @configmirror.content_hash(object) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  try {
    let resource = @orbitops_plane.ResourceId::new(
      kind="ConfigMap",
      name="\{namespace_name}/\{object.name()}",
    )
    let spec = @orbitops_plane.ResourceSpec::new(
      version="configmap",
      replicas=1,
      config_fingerprint=fingerprint,
      enabled=true,
    )
    Ok(
      @orbitops_plane.DesiredState::new(
        resource~,
        spec~,
        generation=desired_generation,
      ),
    )
  } catch {
    _ => Err("ConfigMap cannot be represented as an OrbitOps desired state")
  }
}

///|
pub fn observed_from_configmap(
  object : @object.DynamicObject,
  observed_generation : Int,
) -> Result[@orbitops_plane.ObservedState, String] {
  guard object.namespace_name() is Some(namespace_name) else {
    return Err("ConfigMap must have a namespace")
  }
  let fingerprint = match @configmirror.content_hash(object) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  try {
    let resource = @orbitops_plane.ResourceId::new(
      kind="ConfigMap",
      name="\{namespace_name}/\{object.name()}",
    )
    let spec = @orbitops_plane.ResourceSpec::new(
      version="configmap",
      replicas=1,
      config_fingerprint=fingerprint,
      enabled=true,
    )
    Ok(
      @orbitops_plane.ObservedState::new(
        resource~,
        spec~,
        generation=observed_generation,
        healthy=true,
      ),
    )
  } catch {
    _ => Err("ConfigMap cannot be represented as an OrbitOps observed state")
  }
}

///|
fn configmap(namespace_name : String, value : String) -> @object.DynamicObject {
  @object.DynamicObject::from_json(
    Json::object(
      Map([
        ("apiVersion", Json::string("v1")),
        ("kind", Json::string("ConfigMap")),
        (
          "metadata",
          Json::object(
            Map([
              ("name", Json::string("settings")),
              ("namespace", Json::string(namespace_name)),
              ("resourceVersion", Json::string("opaque-kube-version")),
            ]),
          ),
        ),
        ("data", Json::object(Map([("mode", Json::string(value))]))),
      ]),
    ),
  )
}

///|
fn scenario() -> Result[
  (@orbitops_plane.ValidationStatus, @orbitops_plane.ValidationStatus, Int),
  String,
] {
  let desired : Array[@orbitops_plane.DesiredState] = []
  let observed : Array[@orbitops_plane.ObservedState] = []
  for namespace_name in ["east", "west"] {
    match desired_from_configmap(configmap(namespace_name, "new"), 2) {
      Ok(value) => desired.push(value)
      Err(message) => return Err(message)
    }
    match observed_from_configmap(configmap(namespace_name, "old"), 1) {
      Ok(value) => observed.push(value)
      Err(message) => return Err(message)
    }
  }
  try {
    let budget = @orbitops_plane.ChangeBudget::new(
      max_parallel=1,
      max_affected_resources=1,
      isolate_high_risk=false,
    )
    let policy = @orbitops_plane.SafetyPolicy::new(
      critical_resources=[],
      max_batch_operations=1,
      max_affected_resources=1,
    )
    let plan = @orbitops_plane.build_resource_plan(
      id=@orbitops_plane.PlanId::new(value="kubemoon-1"),
      desired~,
      observed~,
      dependencies=[],
      baseline_generation=1,
      budget~,
    )
    let initial = @orbitops_plane.validate_change_plan({
      plan,
      desired,
      snapshot: { generation: 1, states: observed, absent: [], },
      dependencies: [],
      budget,
      policy,
      approval: @orbitops_plane.ApprovalState::NotRequired,
      feedback: [],
      dispatch_index: 0,
    })
    let started = @orbitops_plane.start_reconciliation(
      plan,
      observed_generation=1,
    )
    let ready = @orbitops_plane.evaluate_reconciliation(started, policy)
    let executing = @orbitops_plane.begin_execution(
      ready,
      observed_generation=1,
    )
    let first = @orbitops_plane.next_reconciliation_operation(
      executing,
      observed_generation=1,
    )
    let feedback = @orbitops_plane.ExecutionResult::new(
      plan_id=plan.plan.id,
      operation=first,
      state=@orbitops_plane.ExecutionState::Succeeded,
      message="simulated host applied the first ConfigMap",
    )
    let partial = @orbitops_plane.apply_execution_result(executing, feedback)
    let updated : Array[@orbitops_plane.ObservedState] = []
    for namespace_name in ["east", "west"] {
      let value = if namespace_name == "east" { "new" } else { "old" }
      match observed_from_configmap(configmap(namespace_name, value), 2) {
        Ok(state) => updated.push(state)
        Err(message) => return Err(message)
      }
    }
    let stale = @orbitops_plane.validate_change_plan({
      plan,
      desired,
      snapshot: { generation: 2, states: updated, absent: [], },
      dependencies: [],
      budget,
      policy,
      approval: @orbitops_plane.ApprovalState::NotRequired,
      feedback: [feedback],
      dispatch_index: 1,
    })
    let replanned = @orbitops_plane.replan_remaining(
      partial,
      id=@orbitops_plane.PlanId::new(value="kubemoon-2"),
      desired~,
      observed=updated,
      dependencies=[],
      observed_generation=2,
      budget~,
    )
    Ok((initial.status, stale.status, replanned.plan.operations.length()))
  } catch {
    _ => Err("KubeMoon boundary example could not complete the plan lifecycle")
  }
}

///|
fn status_name(status : @orbitops_plane.ValidationStatus) -> String {
  match status {
    @orbitops_plane.ValidationStatus::Valid => "valid"
    @orbitops_plane.ValidationStatus::Invalid => "invalid"
    @orbitops_plane.ValidationStatus::Stale => "stale"
  }
}

///|
fn main {
  match scenario() {
    Ok((initial, stale, remaining)) =>
      println(
        "initial=\{status_name(initial)} stale=\{status_name(stale)} remaining=\{remaining}",
      )
    Err(message) => println("error=\{message}")
  }
}

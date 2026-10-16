///|
fn rollout_resource(
  kind~ : String,
  name~ : String,
) -> @orbitops_plane.ResourceId raise @orbitops_plane.ModelError {
  @orbitops_plane.ResourceId::new(kind~, name~)
}

///|
fn rollout_spec(
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
fn rollout_desired(
  resource : @orbitops_plane.ResourceId,
  spec : @orbitops_plane.ResourceSpec,
) -> @orbitops_plane.DesiredState raise @orbitops_plane.ModelError {
  @orbitops_plane.DesiredState::new(resource~, spec~, generation=2)
}

///|
fn rollout_observed(
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
fn build_rollout() -> @orbitops_plane.BatchedPlan raise @orbitops_plane.ModelError {
  let database = try! rollout_resource(kind="database", name="primary")
  let api = try! rollout_resource(kind="service", name="api")
  let worker = try! rollout_resource(kind="worker", name="jobs")
  let desired = [
    try! rollout_desired(database, try! rollout_spec("v1", 1, "db-v2")),
    try! rollout_desired(api, try! rollout_spec("v2", 2, "api")),
    try! rollout_desired(worker, try! rollout_spec("v1", 4, "worker")),
  ]
  let observed = [
    try! rollout_observed(database, try! rollout_spec("v1", 1, "db-v1")),
    try! rollout_observed(api, try! rollout_spec("v1", 2, "api")),
    try! rollout_observed(worker, try! rollout_spec("v1", 2, "worker")),
  ]
  let dependencies : Array[
    (@orbitops_plane.ResourceId, @orbitops_plane.ResourceId),
  ] = [(database, api), (api, worker)]
  @orbitops_plane.build_resource_plan(
    id=@testing.fixed_plan_id(),
    desired~,
    observed~,
    dependencies~,
    baseline_generation=1,
    budget=@orbitops_plane.ChangeBudget::new(
      max_parallel=2,
      max_affected_resources=2,
      isolate_high_risk=false,
    ),
  )
}

///|
fn execute_rollout(
  plan : @orbitops_plane.BatchedPlan,
) -> @orbitops_plane.Reconciliation raise @orbitops_plane.ModelError {
  let policy = @orbitops_plane.SafetyPolicy::new(
    critical_resources=[],
    max_batch_operations=2,
    max_affected_resources=2,
  )
  let started = @orbitops_plane.start_reconciliation(
    plan,
    observed_generation=1,
  )
  let ready = @orbitops_plane.evaluate_reconciliation(started, policy)
  let executing = @orbitops_plane.begin_execution(ready, observed_generation=1)
  let mut current = executing
  while current.state == @orbitops_plane.ReconciliationState::Executing {
    let operation = @orbitops_plane.next_reconciliation_operation(
      current,
      observed_generation=1,
    )
    let run = @testing.fixed_executor(script=@testing.success_script()).run([
      operation,
    ])
    current = @orbitops_plane.apply_execution_result(current, run.results()[0])
  }
  current
}

///|
fn operation_label(operation : @orbitops_plane.Operation) -> String {
  "\{operation.resource.kind}/\{operation.resource.name}:\{action_label(operation.action)}"
}

///|
fn operation_list_label(
  operations : Array[@orbitops_plane.Operation],
) -> String {
  let mut result = ""
  for index, operation in operations {
    if index > 0 {
      result = result + ", "
    }
    result = result + operation_label(operation)
  }
  result
}

///|
fn action_label(action : @orbitops_plane.ActionKind) -> String {
  match action {
    @orbitops_plane.ActionKind::Create => "create"
    @orbitops_plane.ActionKind::Update => "update"
    @orbitops_plane.ActionKind::Scale => "scale"
    @orbitops_plane.ActionKind::Restart => "restart"
    @orbitops_plane.ActionKind::Delete => "delete"
    @orbitops_plane.ActionKind::Unknown => "unknown"
  }
}

///|
fn policy_decision_label(decision : @orbitops_plane.PolicyDecision) -> String {
  match decision {
    @orbitops_plane.PolicyDecision::Allow => "allow"
    @orbitops_plane.PolicyDecision::Deny => "deny"
    @orbitops_plane.PolicyDecision::RequireApproval => "require-approval"
  }
}

///|
fn risk_label(risk : @orbitops_plane.RiskLevel) -> String {
  match risk {
    @orbitops_plane.RiskLevel::Low => "low"
    @orbitops_plane.RiskLevel::Medium => "medium"
    @orbitops_plane.RiskLevel::High => "high"
    @orbitops_plane.RiskLevel::Unknown => "unknown"
  }
}

///|
fn reason_label(reason : @orbitops_plane.PolicyReasonCode) -> String {
  match reason {
    @orbitops_plane.PolicyReasonCode::LowRisk => "low-risk"
    @orbitops_plane.PolicyReasonCode::MediumRisk => "medium-risk"
    @orbitops_plane.PolicyReasonCode::HighRiskAction => "high-risk-action"
    @orbitops_plane.PolicyReasonCode::DeleteProtection => "delete-protection"
    @orbitops_plane.PolicyReasonCode::BatchRestart => "batch-restart"
    @orbitops_plane.PolicyReasonCode::CriticalResource => "critical-resource"
    @orbitops_plane.PolicyReasonCode::BudgetConflict => "budget-conflict"
    @orbitops_plane.PolicyReasonCode::UnknownAction => "unknown-action"
  }
}

///|
fn state_label(state : @orbitops_plane.ReconciliationState) -> String {
  match state {
    @orbitops_plane.ReconciliationState::Planning => "planning"
    @orbitops_plane.ReconciliationState::AwaitingApproval => "awaiting-approval"
    @orbitops_plane.ReconciliationState::Ready => "ready"
    @orbitops_plane.ReconciliationState::Executing => "executing"
    @orbitops_plane.ReconciliationState::Succeeded => "succeeded"
    @orbitops_plane.ReconciliationState::Failed => "failed"
    @orbitops_plane.ReconciliationState::Terminated => "terminated"
  }
}

///|
fn audit_kind_label(kind : @orbitops_plane.AuditEventKind) -> String {
  match kind {
    @orbitops_plane.AuditEventKind::PlanCreated => "plan-created"
    @orbitops_plane.AuditEventKind::PolicyDecision => "policy-decision"
    @orbitops_plane.AuditEventKind::Approval => "approval"
    @orbitops_plane.AuditEventKind::StateTransition => "state-transition"
    @orbitops_plane.AuditEventKind::ExecutionFeedback => "execution-feedback"
    @orbitops_plane.AuditEventKind::Terminal => "terminal"
  }
}

///|
fn run_rollout() -> Unit {
  try {
    let plan = build_rollout()
    let result = execute_rollout(plan)
    println("OrbitOps dependency-aware rollout")
    println(
      "plan=\{result.plan.plan.id.value} baseline=\{result.observed_generation}",
    )
    println("ordered=\{operation_list_label(result.plan.plan.operations)}")
    for index, batch in result.plan.batches {
      println("batch[\{index}]=\{operation_list_label(batch.operations)}")
    }
    for index, decision in result.decisions {
      println(
        "policy[\{index}]=\{policy_decision_label(decision.decision)} " +
        "risk=\{risk_label(decision.risk)} " +
        "reason=\{reason_label(decision.reason_code)}",
      )
    }
    for index, feedback in result.results {
      println(
        "feedback[\{index}]=\{operation_label(feedback.operation)} " +
        "state=\{execution_state_label(feedback.state)}",
      )
    }
    for event in result.audit_events {
      println(
        "audit[\{event.sequence}]=\{audit_kind_label(event.kind)} " +
        "state=\{state_label(event.state)}",
      )
    }
    println("state=\{state_label(result.state)}")
  } catch {
    _ => println("rollout failed")
  }
}

///|
fn execution_state_label(state : @orbitops_plane.ExecutionState) -> String {
  match state {
    @orbitops_plane.ExecutionState::Succeeded => "succeeded"
    @orbitops_plane.ExecutionState::Failed => "failed"
    @orbitops_plane.ExecutionState::Skipped => "skipped"
  }
}

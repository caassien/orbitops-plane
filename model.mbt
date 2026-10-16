///|
/// Errors raised while constructing or validating the operations model.
pub(all) suberror ModelError {
  EmptyField(String)
  NegativeReplicas
  NonPositiveGeneration
  ResourceMismatch
  InvalidDependency(String)
  DependencyCycle(String)
  DuplicateOperation(String)
  DuplicateResource(String)
  InvalidBudget(String)
  InvalidTransition(String)
  DuplicateFeedback(String)
  StaleObservation(String)
  StalePlan(String)
  PlanMismatch(String)
  InvalidAudit(String)
} derive(Debug, Eq)

///|
/// Stable identity of a managed resource.
pub(all) struct ResourceId {
  kind : String
  name : String
} derive(Debug, Eq)

///|
/// Creates a validated resource identity.
pub fn ResourceId::new(
  kind~ : String,
  name~ : String,
) -> ResourceId raise ModelError {
  if kind == "" {
    raise ModelError::EmptyField("kind")
  }
  if name == "" {
    raise ModelError::EmptyField("name")
  }
  { kind, name, }
}

///|
/// Desired configuration for a managed resource.
pub(all) struct ResourceSpec {
  version : String
  replicas : Int
  config_fingerprint : String
  enabled : Bool
} derive(Debug, Eq)

///|
/// Creates a validated resource specification.
pub fn ResourceSpec::new(
  version~ : String,
  replicas~ : Int,
  config_fingerprint~ : String,
  enabled~ : Bool,
) -> ResourceSpec raise ModelError {
  if version == "" {
    raise ModelError::EmptyField("version")
  }
  if replicas < 0 {
    raise ModelError::NegativeReplicas
  }
  if config_fingerprint == "" {
    raise ModelError::EmptyField("config_fingerprint")
  }
  { version, replicas, config_fingerprint, enabled, }
}

///|
/// Desired state supplied by a caller.
pub(all) struct DesiredState {
  resource : ResourceId
  spec : ResourceSpec
  generation : Int
} derive(Debug, Eq)

///|
/// Creates a desired state with a positive generation.
pub fn DesiredState::new(
  resource~ : ResourceId,
  spec~ : ResourceSpec,
  generation~ : Int,
) -> DesiredState raise ModelError {
  if generation <= 0 {
    raise ModelError::NonPositiveGeneration
  }
  { resource, spec, generation, }
}

///|
/// State reported by an observation adapter.
pub(all) struct ObservedState {
  resource : ResourceId
  spec : ResourceSpec
  generation : Int
  healthy : Bool
} derive(Debug, Eq)

///|
/// Creates an observed state with a positive generation.
pub fn ObservedState::new(
  resource~ : ResourceId,
  spec~ : ResourceSpec,
  generation~ : Int,
  healthy~ : Bool,
) -> ObservedState raise ModelError {
  if generation <= 0 {
    raise ModelError::NonPositiveGeneration
  }
  { resource, spec, generation, healthy, }
}

///|
/// Kinds of side effects that a future planner may request.
pub(all) enum ActionKind {
  Create
  Update
  Scale
  Restart
  Delete
  Unknown
} derive(Debug, Eq)

///|
/// A single requested operation and its human-readable reason.
pub(all) struct Operation {
  resource : ResourceId
  action : ActionKind
  reason : String
} derive(Debug, Eq)

///|
/// Creates an operation with a non-empty explanation.
pub fn Operation::new(
  resource~ : ResourceId,
  action~ : ActionKind,
  reason~ : String,
) -> Operation raise ModelError {
  if reason == "" {
    raise ModelError::EmptyField("reason")
  }
  { resource, action, reason, }
}

///|
/// Identifier for a generated operation plan.
pub(all) struct PlanId {
  value : String
} derive(Debug, Eq)

///|
/// Creates a non-empty plan identifier.
pub fn PlanId::new(value~ : String) -> PlanId raise ModelError {
  if value == "" {
    raise ModelError::EmptyField("plan_id")
  }
  { value, }
}

///|
/// Approval state attached to an operation plan.
pub(all) enum ApprovalState {
  NotRequired
  Pending
  Approved
  Rejected
} derive(Debug, Eq)

///|
/// A deterministic collection of operations based on one observed generation.
pub(all) struct Plan {
  id : PlanId
  operations : Array[Operation]
  baseline_generation : Int
  approval : ApprovalState
} derive(Debug, Eq)

///|
/// Creates a plan awaiting any future policy evaluation.
pub fn Plan::new(
  id~ : PlanId,
  operations~ : Array[Operation],
  baseline_generation~ : Int,
) -> Plan raise ModelError {
  if baseline_generation <= 0 {
    raise ModelError::NonPositiveGeneration
  }
  { id, operations, baseline_generation, approval: ApprovalState::NotRequired, }
}

///|
/// Terminal result of applying one operation.
pub(all) enum ExecutionState {
  Succeeded
  Failed
  Skipped
} derive(Debug, Eq)

///|
/// Feedback returned by an execution adapter.
pub(all) struct ExecutionResult {
  plan_id : PlanId
  operation : Operation
  state : ExecutionState
  message : String
} derive(Debug, Eq)

///|
/// Creates an execution result with a non-empty message.
pub fn ExecutionResult::new(
  plan_id~ : PlanId,
  operation~ : Operation,
  state~ : ExecutionState,
  message~ : String,
) -> ExecutionResult raise ModelError {
  if message == "" {
    raise ModelError::EmptyField("message")
  }
  { plan_id, operation, state, message, }
}

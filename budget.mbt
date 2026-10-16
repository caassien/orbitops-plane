///|
/// Limits applied when a plan is split into executable change batches.
pub(all) struct ChangeBudget {
  max_parallel : Int
  max_affected_resources : Int
  isolate_high_risk : Bool
} derive(Debug, Eq)

///|
/// Creates a budget with positive action and resource limits.
pub fn ChangeBudget::new(
  max_parallel~ : Int,
  max_affected_resources~ : Int,
  isolate_high_risk~ : Bool,
) -> ChangeBudget raise ModelError {
  if max_parallel <= 0 {
    raise ModelError::InvalidBudget("max_parallel must be positive")
  }
  if max_affected_resources <= 0 {
    raise ModelError::InvalidBudget("max_affected_resources must be positive")
  }
  { max_parallel, max_affected_resources, isolate_high_risk, }
}

///|
/// A non-empty executable group of operations.
pub(all) struct ChangeBatch {
  operations : Array[Operation]
} derive(Debug, Eq)

///|
/// A plan together with its budget-constrained execution batches.
pub(all) struct BatchedPlan {
  plan : Plan
  batches : Array[ChangeBatch]
} derive(Debug, Eq)

///|
fn is_high_risk(operation : Operation) -> Bool {
  operation.action == ActionKind::Delete ||
  operation.action == ActionKind::Restart
}

///|
fn contains_resource(
  operations : Array[Operation],
  resource : ResourceId,
) -> Bool {
  let mut found = false
  for operation in operations {
    if operation.resource == resource {
      found = true
    }
  }
  found
}

///|
fn contains_resource_id(
  resources : Array[ResourceId],
  resource : ResourceId,
) -> Bool {
  let mut found = false
  for candidate in resources {
    if candidate == resource {
      found = true
    }
  }
  found
}

///|
fn affected_resource_count(operations : Array[Operation]) -> Int {
  let resources : Array[ResourceId] = []
  for operation in operations {
    if !contains_resource_id(resources, operation.resource) {
      resources.push(operation.resource)
    }
  }
  resources.length()
}

///|
fn add_batch(
  batches : Array[ChangeBatch],
  operations : Array[Operation],
) -> Unit {
  if operations.length() > 0 {
    batches.push({ operations, })
  }
}

///|
/// Splits an ordered plan into deterministic, budget-constrained batches.
///
/// The input operation order is preserved. A batch never exceeds either
/// configured limit. Delete and restart operations are isolated when the
/// corresponding budget flag is enabled.
pub fn batch_plan(
  plan : Plan,
  budget : ChangeBudget,
) -> BatchedPlan raise ModelError {
  batch_plan_internal(plan, budget, [])
}

///|
fn dependency_path_exists(
  source : ResourceId,
  target : ResourceId,
  dependencies : Array[(ResourceId, ResourceId)],
  reverse_dependencies : Bool,
) -> Bool {
  let visited : Array[ResourceId] = [source]
  let mut index = 0
  while index < visited.length() {
    let current = visited[index]
    for edge in dependencies {
      let (dependency, dependent) = edge
      let from = if reverse_dependencies { dependent } else { dependency }
      let to = if reverse_dependencies { dependency } else { dependent }
      if from == current {
        if to == target {
          return true
        }
        if !contains_resource_id(visited, to) {
          visited.push(to)
        }
      }
    }
    index += 1
  }
  false
}

///|
fn batch_has_predecessor(
  current : Array[Operation],
  candidate : Operation,
  dependencies : Array[(ResourceId, ResourceId)],
  reverse_dependencies : Bool,
) -> Bool {
  for operation in current {
    if dependency_path_exists(
        operation.resource,
        candidate.resource,
        dependencies,
        reverse_dependencies,
      ) {
      return true
    }
  }
  false
}

///|
/// Batches a dependency-ordered plan. A dependent cannot share a batch with
/// any predecessor, including one connected through an unchanged resource.
pub fn batch_plan_with_dependencies(
  plan : Plan,
  budget : ChangeBudget,
  dependencies : Array[(ResourceId, ResourceId)],
) -> BatchedPlan raise ModelError {
  let ordered = order_operations(
    plan.operations,
    dependencies,
    reverse_dependencies=only_deletes(plan.operations),
  )
  for index in 0..<ordered.length() {
    if ordered[index] != plan.operations[index] {
      raise ModelError::InvalidDependency("plan is not dependency ordered")
    }
  }
  batch_plan_internal(plan, budget, dependencies)
}

///|
fn batch_plan_internal(
  plan : Plan,
  budget : ChangeBudget,
  dependencies : Array[(ResourceId, ResourceId)],
) -> BatchedPlan raise ModelError {
  if budget.max_parallel <= 0 {
    raise ModelError::InvalidBudget("max_parallel must be positive")
  }
  if budget.max_affected_resources <= 0 {
    raise ModelError::InvalidBudget("max_affected_resources must be positive")
  }
  let resources = collect_resources(plan.operations, dependencies)
  validate_resource_dependencies(resources, dependencies)
  validate_unique_operations(plan.operations)
  let reverse_dependencies = only_deletes(plan.operations)
  let batches : Array[ChangeBatch] = []
  let mut current : Array[Operation] = []
  for operation in plan.operations {
    let current_resources = affected_resource_count(current)
    let operation_is_new_resource = !contains_resource(
      current,
      operation.resource,
    )
    let exceeds_parallel = current.length() >= budget.max_parallel
    let exceeds_resources = operation_is_new_resource &&
      current_resources >= budget.max_affected_resources
    if budget.isolate_high_risk && is_high_risk(operation) {
      add_batch(batches, current)
      current = []
      add_batch(batches, [operation])
    } else if exceeds_parallel ||
      exceeds_resources ||
      batch_has_predecessor(
        current, operation, dependencies, reverse_dependencies,
      ) {
      add_batch(batches, current)
      current = [operation]
    } else {
      current.push(operation)
    }
  }
  add_batch(batches, current)
  { plan, batches, }
}

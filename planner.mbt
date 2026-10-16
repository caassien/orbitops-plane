///|
fn resource_index(resources : Array[ResourceId], resource : ResourceId) -> Int? {
  let mut result : Int? = None
  for i, current in resources {
    if result is None && current == resource {
      result = Some(i)
    }
  }
  result
}

///|
fn collect_resources(
  operations : Array[Operation],
  dependencies : Array[(ResourceId, ResourceId)],
) -> Array[ResourceId] {
  let resources : Array[ResourceId] = []
  for operation in operations {
    if resource_index(resources, operation.resource) is None {
      resources.push(operation.resource)
    }
  }
  for i in 0..<dependencies.length() {
    let (dependency, dependent) = dependencies[i]
    if resource_index(resources, dependency) is None {
      resources.push(dependency)
    }
    if resource_index(resources, dependent) is None {
      resources.push(dependent)
    }
  }
  resources
}

///|
fn validate_unique_operations(
  operations : Array[Operation],
) -> Unit raise ModelError {
  for i in 0..<operations.length() {
    for j in 0..<i {
      if operations[i].resource == operations[j].resource {
        raise ModelError::DuplicateOperation(
          resource_key(operations[i].resource),
        )
      }
    }
  }
}

///|
fn only_deletes(operations : Array[Operation]) -> Bool {
  let mut result = operations.length() > 0
  for operation in operations {
    if operation.action != ActionKind::Delete {
      result = false
    }
  }
  result
}

///|
fn add_order_edge(
  adjacency : Array[Array[Int]],
  indegree : Array[Int],
  source : Int,
  target : Int,
) -> Unit {
  let mut exists = false
  for current in adjacency[source] {
    if current == target {
      exists = true
    }
  }
  if !exists {
    adjacency[source].push(target)
    indegree[target] = indegree[target] + 1
  }
}

///|
fn choose_ready_operation(
  operations : Array[Operation],
  selected : Array[Bool],
  indegree : Array[Int],
) -> Int? {
  let mut candidate : Int? = None
  for i in 0..<operations.length() {
    if !selected[i] && indegree[i] == 0 {
      match candidate {
        None => candidate = Some(i)
        Some(current) =>
          if resource_key(operations[i].resource) <
            resource_key(operations[current].resource) {
            candidate = Some(i)
          }
      }
    }
  }
  candidate
}

///|
fn order_operations(
  operations : Array[Operation],
  dependencies : Array[(ResourceId, ResourceId)],
  reverse_dependencies~ : Bool,
) -> Array[Operation] raise ModelError {
  let adjacency : Array[Array[Int]] = []
  let indegree : Array[Int] = []
  let selected : Array[Bool] = []
  for _ in 0..<operations.length() {
    adjacency.push([])
    indegree.push(0)
    selected.push(false)
  }
  for source in 0..<operations.length() {
    for target in 0..<operations.length() {
      if source != target &&
        dependency_path_exists(
          operations[source].resource,
          operations[target].resource,
          dependencies,
          reverse_dependencies,
        ) {
        add_order_edge(adjacency, indegree, source, target)
      }
    }
  }
  let order : Array[Int] = []
  for _ in 0..<operations.length() {
    let next = match choose_ready_operation(operations, selected, indegree) {
      Some(index) => index
      None => raise ModelError::DependencyCycle("operation plan")
    }
    selected[next] = true
    order.push(next)
    for dependent in adjacency[next] {
      indegree[dependent] = indegree[dependent] - 1
    }
  }
  let ordered : Array[Operation] = []
  for index in order {
    ordered.push(operations[index])
  }
  ordered
}

///|
/// Builds a stable dependency-ordered plan from candidate operations.
///
/// Dependency pairs use `(dependency, dependent)` order. Create, update,
/// scale and restart operations run dependency-first; an all-delete plan
/// runs dependent-first. Independent operations are ordered by resource key,
/// so changing the input array order does not change the plan.
pub fn build_ordered_plan(
  id~ : PlanId,
  operations~ : Array[Operation],
  dependencies~ : Array[(ResourceId, ResourceId)],
  baseline_generation~ : Int,
) -> Plan raise ModelError {
  let resources = collect_resources(operations, dependencies)
  validate_resource_dependencies(resources, dependencies)
  validate_unique_operations(operations)
  let ordered = order_operations(
    operations,
    dependencies,
    reverse_dependencies=only_deletes(operations),
  )
  Plan::new(id~, operations=ordered, baseline_generation~)
}

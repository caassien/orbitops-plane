///|
test "KubeMoon dynamic ConfigMaps drive validation and replan" {
  match scenario() {
    Ok((initial, stale, remaining)) => {
      assert_eq(initial, @orbitops_plane.ValidationStatus::Valid)
      assert_eq(stale, @orbitops_plane.ValidationStatus::Stale)
      assert_eq(remaining, 1)
    }
    Err(message) => fail(message)
  }
}

///|
test "KubeMoon adapter rejects cluster-scoped ConfigMap inputs" {
  let object = @object.DynamicObject::from_json(
    Json::object(
      Map([
        ("metadata", Json::object(Map([("name", Json::string("settings"))]))),
      ]),
    ),
  )
  assert_true(desired_from_configmap(object, 1) is Err(_))
}

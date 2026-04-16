test "hello returns expected message" {
  inspect(hello(), content="\"hello from moapi\"")
}

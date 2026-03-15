import shogg/vtodo

pub type Msg {
  ShoggFetchedTodos(List(vtodo.VTodo))
  ShoggSendUpdate
  UserAddedTodo(summary: String)
  UserCheckedTodo(uid: String, checked: Bool)
  UserRenamedTodo(uid: String, summary: String)
  UserDeletedTodo(uid: String)
  UserClickedReload
}

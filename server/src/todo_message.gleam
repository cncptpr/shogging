import shogg/calendar.{type Calendar}
import shogg/vtodo

pub type Msg {
  ShoggFetchedTodos(List(vtodo.VTodo))
  ShoggSendUpdate(vtodo.VTodo)
  ShoggDetectedChange(Calendar)
  UserAddedTodo(summary: String)
  UserCheckedTodo(uid: String, checked: Bool)
  UserRenamedTodo(uid: String, summary: String)
  UserDeletedTodo(uid: String)
  UserClickedReload
}

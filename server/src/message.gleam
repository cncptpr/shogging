import shogg/calendar.{type Calendar}
import shogg/task

pub type Msg {
  ShoggFetchedTasks(List(task.Task))
  ShoggSendUpdate(task.Task)
  ShoggDetectedChange(Calendar)
  UserAddedTask(summary: String)
  UserCheckedTask(uid: String, checked: Bool)
  UserRenamedTask(uid: String, summary: String)
  UserDeletedTask(uid: String)
  UserClickedReload
}

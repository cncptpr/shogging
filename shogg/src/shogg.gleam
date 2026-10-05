import shogxml

pub type ShoggError(error) {
  SendError(error)
  XmlDecodeError(shogxml.Error)
  ParseError(String)
}

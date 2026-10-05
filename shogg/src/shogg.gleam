import xml

pub type ShoggError(error) {
  SendError(error)
  XmlDecodeError(xml.Error)
  ParseError(String)
}

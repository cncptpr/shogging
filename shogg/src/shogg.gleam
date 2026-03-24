import parsed_it/xml

pub type ShoggError(error) {
  SendError(error)
  XmlDecodeError(xml.XmlDecodeError)
  ParseError(String)
}

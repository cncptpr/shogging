import parsed_it/xml

pub type ShoggError(error) {
  SendError(error)
  DecodeError(xml.XmlDecodeError)
  ParseError(String)
}

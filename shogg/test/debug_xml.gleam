import gleam/dynamic/decode
import parsed_it/xml

pub fn main() {
  let xml =
    "<?xml version='1.0' encoding='utf-8'?><multistatus xmlns=\"DAV:\"><response><href>/test/</href></response></multistatus>"
  let result = xml.parse(xml, decode.dynamic)
  case result {
    Ok(d) -> {
      echo d
      // Try to decode as dict
      let dict_result =
        decode.run(d, decode.dict(decode.string, decode.dynamic))
      echo dict_result
    }
    Error(e) -> {
      echo e
      todo
    }
  }
}

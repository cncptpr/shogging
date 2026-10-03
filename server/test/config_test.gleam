import config

pub fn port_falls_back_when_unset_test() {
  assert config.port_from_value("") == config.default_port
}

pub fn port_falls_back_when_not_a_number_test() {
  assert config.port_from_value("http") == config.default_port
}

pub fn port_is_read_when_set_test() {
  assert config.port_from_value("8080") == 8080
}
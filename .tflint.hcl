# tflint for the Coder templates (mise run lint:templates). tflint checks the language and style;
# deprecated provider attributes come from `terraform validate` (the provider's schema).
config {
  call_module_type = "none"
}

plugin "terraform" {
  enabled = true
  preset  = "all"
}

# A template is one root module in one file: no variables.tf/outputs.tf.
rule "terraform_standard_module_structure" {
  enabled = false
}

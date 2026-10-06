# El bloque backend se evalúa en la inicialización, antes de que existan
# variables, locals y data sources: solo acepta literales. Por eso el account
# ID está escrito acá y en ningún otro lugar del repo.
#
# El bucket lo crea backend/. Si cambia de nombre, se cambia también acá.
terraform {
  backend "s3" {
    bucket = "lab3-lc-tfstate-104981180500"
    key    = "dev/terraform.tfstate"
    region = "us-east-1"

    encrypt = true

    # Lock nativo de S3: escribe dev/terraform.tfstate.tflock mientras dura
    # la operación. Reemplaza a DynamoDB — lo exige el enunciado.
    use_lockfile = true
  }
}

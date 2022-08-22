const deployables = require('./getDeployablesInTfState')()

if (deployables.length > 0) {
  console.log()
  console.log('──────')
  console.log()
  console.log('Got ' + deployables.length + ' systems in Terraform configuration, deploy with:')
  console.log()
  for (const deployable of deployables) {
    console.log('deployNixOSSystem ' + deployable.tfKey)
  }
  console.log()
  console.log('Append one of {boot,switch,switch-unsafe} to the command to choose deployment method')
  console.log()
  console.log('──────')
  console.log()
}

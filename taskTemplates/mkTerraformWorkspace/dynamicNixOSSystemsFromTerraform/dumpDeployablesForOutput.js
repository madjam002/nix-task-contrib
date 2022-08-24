const deployables = require('./getDeployablesInTfState')()

console.log(JSON.stringify(deployables.map(deployable => ({
  systemAttribute: deployable.attribute,
  args: deployable.args,
  remote: deployable.remote,
}))))

const { spawnSync } = require('child_process')

const deployables = require('./getDeployablesInTfState')()

const tfKey = process.argv[2]
const switchMode = process.argv[3]

const manifest = deployables.find(deployable => deployable.tfKey === tfKey)

if (!manifest) {
  console.log('System with provided key not found')
  console.log()
  process.exit(1)
}

try {
  spawnSync(manifest.deployCommandBase[0], [...manifest.deployCommandBase.slice(1), switchMode], {
    stdio: 'inherit'
  })
} catch (ex) {}

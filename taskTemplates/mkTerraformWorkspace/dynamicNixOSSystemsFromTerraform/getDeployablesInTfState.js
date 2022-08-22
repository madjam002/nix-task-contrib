const { execSync } = require('child_process')

module.exports = function getDeployablesInTfState() {
  const tfState = JSON.parse(execSync('terraform state pull').toString())

  const dataSources = tfState.resources.filter(
    (resource) => resource.mode === 'data'
  )

  function findMatchingDataSourceForSystem(resourceInstance) {
    for (const dataSource of dataSources) {
      if (dataSource.type === 'external') {
        for (const instance of dataSource.instances) {
          if (
            instance?.attributes?.program?.[0] === 'tfQueryDynamicNixOSSystem' &&
            instance?.attributes?.result?.out ===
              resourceInstance?.attributes?.triggers?.system
          ) {
            const [__, dynamicSystemAttribute] = instance.attributes.program
            if (dynamicSystemAttribute != null) {
              return {
                attribute: dynamicSystemAttribute,
                args: instance?.attributes?.query ?? {},
              }
            }
          }
        }
      }
    }
  }

  const manifests = []

  for (const resource of tfState.resources) {
    if (resource.mode === 'managed' && resource.type === 'null_resource') {
      for (const instance of resource.instances) {
        if (
          instance?.attributes?.triggers?.remote != null &&
          instance?.attributes?.triggers?.system != null
        ) {
          const systemDataSource = findMatchingDataSourceForSystem(instance)

          const manifest = {
            attribute: systemDataSource.attribute,
            args: systemDataSource.args,
            remote: instance?.attributes?.triggers?.remote,
            tfKey: [
              resource.name,
              instance.index_key != null ? `[${instance.index_key}]` : null,
            ]
              .filter((part) => !!part)
              .join(''),
          }

          manifest.deployCommandBase = [
            'deployDynamicNixOSSystem',
            manifest.attribute,
            manifest.remote,
            JSON.stringify(manifest.args),
          ]

          manifests.push(manifest)
        }
      }
    }
  }

  return manifests
}

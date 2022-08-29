#!/usr/bin/env zx

let sshConfig = ''

try {
  sshConfig = fs.readFileSync(process.env.HOME + '/.ssh/config', 'utf8')
} catch (ex) {}

const [__, remote, ...opts] = argv._

const [user, host] = remote.split('@')

const lines = sshConfig.split('\n')
let out = ''
let didUpdate = false

const formatOpt = (opt) => {
  const split = opt.split('=')
  return `${split[0]} ${split.slice(1).join('=')}`
}

for (let i = 0; i < lines.length; i++) {
  const line = lines[i]

  if (line.toLowerCase().trim() === `host ${host.toLowerCase()}`) {
    out += line + '\n'
    for (const opt of opts) {
      out += `\t${formatOpt(opt)}\n`
    }
    out += '\n'
    didUpdate = true

    const nextIndex = lines.slice(i + 1).findIndex(line => line.trim().toLowerCase().startsWith('host '))
    if (nextIndex >= 0) {
      i = nextIndex + i
    } else {
      i = lines.length
    }
  } else {
    out += line + '\n'
  }
}

if (!didUpdate) {
  out += 'Host ' + host + '\n'
  for (const opt of opts) {
    out += `\t${formatOpt(opt)}\n`
  }
}

fs.ensureDirSync(process.env.HOME + '/.ssh')
fs.writeFileSync(process.env.HOME + '/.ssh/config', out, 'utf8')

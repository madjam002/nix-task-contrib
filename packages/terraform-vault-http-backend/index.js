#!/usr/bin/env node

const axios = require('axios')
const fs = require('fs')
require('express-async-errors')
const app = require('express')()

const vault = axios.create({
  baseURL: process.env.VAULT_ADDR,
})

app.use(require('body-parser').json({ limit: '10MB' }))

app.get('*', async (req, res) => {
  try {
    const vaultRes = await vault.get('/v1' + req.url, {
      headers: {
        'X-Vault-Token': process.env.VAULT_TOKEN || req.query.vaultToken,
      },
    })
    console.log('Read tfstate for', req.url)
    res.send(vaultRes.data.data.data.tfstate)
  } catch (ex) {
    if (ex.response && ex.response.status === 404) {
      console.log('No tfstate for', req.url)
      return res.sendStatus(404)
    }

    throw ex
  }
})

app.post('*', async (req, res) => {
  await vault.post(
    '/v1' + req.url,
    {
      data: {
        tfstate: JSON.stringify(req.body, null, 2),
      },
    },
    {
      headers: {
        'X-Vault-Token': process.env.VAULT_TOKEN || req.query.vaultToken,
      },
    },
  )
  console.log('Updated tfstate for', req.url)
  res.sendStatus(201)
})

const listener = app.listen(process.env.PORT || null, () => {
  // output port to PORT_FILE so it can be read by the calling script
  if (process.env.PORT !== listener.address().port.toString()) {
    fs.writeFileSync(process.env.PORT_FILE, listener.address().port.toString())
  }
})

import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'

function localApiPlugin() {
  return {
    name: 'local-api',
    configureServer(server) {
      const apiDir = path.resolve(process.cwd(), 'api')

      server.middlewares.use(async (req, res, next) => {
        if (!req.url?.startsWith('/api/')) {
          next()
          return
        }

        const pathname = new URL(req.url, 'http://localhost').pathname
        const routePath = pathname.slice('/api/'.length).replace(/\/$/, '')
        const handlerPath = path.resolve(apiDir, `${routePath}.js`)
        const relativeHandlerPath = path.relative(apiDir, handlerPath)

        if (relativeHandlerPath.startsWith('..') || path.isAbsolute(relativeHandlerPath) || !fs.existsSync(handlerPath)) {
          next()
          return
        }

        try {
          const moduleUrl = `${pathToFileURL(handlerPath).href}?t=${Date.now()}`
          const mod = await import(moduleUrl)
          await mod.default(req, res)
        } catch (err) {
          server.config.logger.error(err)
          res.statusCode = 500
          res.setHeader('Content-Type', 'application/json; charset=utf-8')
          res.end(JSON.stringify({ error: 'Local API handler failed.' }))
        }
      })
    },
  }
}

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  Object.assign(process.env, env)

  return {
    plugins: [react(), localApiPlugin()],
  }
})

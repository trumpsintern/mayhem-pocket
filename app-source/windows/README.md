# Windows source

The Windows version is an Electron application. Its visible interface is in `index.html`, `style.css`, and `renderer.js`; desktop startup and network requests are handled by `main.js` and `preload.js`.

To run it locally, install Node.js, run `npm install --no-save electron@44.2.0`, then run `npx electron .`.

The release ZIP contains the packaged application and supporting Electron files. Keep those files together when running the downloaded build.

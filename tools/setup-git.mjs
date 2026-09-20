import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const targetDir = 'C:\\Users\\peteb\\.git-bin';
if (!fs.existsSync(targetDir)) {
  fs.mkdirSync(targetDir, { recursive: true });
}

const zipFile = path.join(targetDir, 'mingit.zip');

function download(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    const request = (targetUrl) => {
      https.get(targetUrl, { headers: { 'User-Agent': 'Node.js' } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          console.log('Redirecting to:', res.headers.location);
          return request(res.headers.location);
        }
        if (res.statusCode !== 200) {
          return reject(new Error(`Failed with status ${res.statusCode}`));
        }
        res.pipe(file);
        file.on('finish', () => {
          file.close(resolve);
        });
      }).on('error', reject);
    };
    request(url);
  });
}

async function run() {
  const url = 'https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.5/MinGit-2.55.0.5-64-bit.zip';
  console.log('Downloading MinGit from', url);
  await download(url, zipFile);
  console.log('Downloaded. Size:', fs.statSync(zipFile).size);

  console.log('Extracting to', targetDir);
  execSync(`tar -xf "${zipFile}" -C "${targetDir}"`, { stdio: 'inherit' });
  fs.unlinkSync(zipFile);

  const gitExe = path.join(targetDir, 'cmd', 'git.exe');
  console.log('Testing git at:', gitExe);
  const version = execSync(`"${gitExe}" --version`, { encoding: 'utf8' });
  console.log('Git successfully installed:', version.trim());
}

run().catch(console.error);

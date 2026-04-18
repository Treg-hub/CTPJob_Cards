const https = require('https');
const { execSync } = require('child_process');

async function callMigrateFunction() {
  try {
    console.log('Getting Firebase access token...');

    // Get Firebase access token
    const token = execSync('# firebase auth:export auth_export.json --format=json  # skipped - new project', { encoding: 'utf8' });
    const tokenData = JSON.parse(token);
    const accessToken = tokenData.tokens.access_token;

    console.log('Calling migrateJobStatuses function...');

    const postData = JSON.stringify({});

    const options = {
      hostname: 'africa-south1-ctp-job-cards.cloudfunctions.net',
      port: 443,
      path: '/migrateJobStatuses',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData),
        'Authorization': `Bearer ${accessToken}`
      }
    };

    return new Promise((resolve, reject) => {
      const req = https.request(options, (res) => {
        let data = '';

        res.on('data', (chunk) => {
          data += chunk;
        });

        res.on('end', () => {
          try {
            const result = JSON.parse(data);
            console.log('Migration completed successfully!');
            console.log('Result:', JSON.stringify(result, null, 2));
            resolve(result);
          } catch (e) {
            console.log('Raw response:', data);
            resolve(data);
          }
        });
      });

      req.on('error', (error) => {
        console.error('Request failed:', error);
        reject(error);
      });

      req.write(postData);
      req.end();
    });

  } catch (error) {
    console.error('Migration failed:', error);
  }
}

// Run the function call
callMigrateFunction();

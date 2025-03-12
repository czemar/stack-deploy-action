import { $, chalk } from "npm:zx";

// Print script information
console.log(chalk.blue(`Current directory: ${process.cwd()}`));

// List repository files
await $`ls -la /github/workspace`;

console.log(process.env);

// Read environment variables from inputs
const INPUT_HOST = process.env.INPUT_HOST;
const INPUT_PORT = process.env.INPUT_PORT || 22;
const INPUT_USER = process.env.INPUT_USER;
const INPUT_PASS = process.env.INPUT_PASS;
const INPUT_SSH_KEY = process.env.INPUT_SSH_KEY;
const INPUT_FILE = process.env.INPUT_FILE;
const INPUT_NAME = process.env.INPUT_NAME;
const INPUT_ENV_FILE = process.env.INPUT_ENV_FILE;
const INPUT_ENV = process.env.INPUT_ENV;

// Function for cleanup trap
async function cleanupTrap() {
    console.log(chalk.red("Cleaning up..."));
    if (!INPUT_SSH_KEY) {
        await $`ssh -p ${INPUT_PORT} ${INPUT_USER}@${INPUT_HOST} "sed -i '/docker-stack-deploy-action/d' ~/.ssh/authorized_keys"`;
    }
    console.log(chalk.green("Finished Successfully."));
}

// Ensure cleanup runs on exit
process.on("exit", cleanupTrap);

// Create SSH directory
await $`mkdir -p /root/.ssh && chmod 0700 /root/.ssh`;

// Add remote host to known_hosts
console.log(chalk.cyan(`Adding host ${INPUT_HOST} to known_hosts...`));
await $`ssh-keyscan -p ${INPUT_PORT} -H ${INPUT_HOST} >> /root/.ssh/known_hosts`;

// Check Docker status
console.log(chalk.cyan("Checking Docker on remote host..."));
await $`ssh -p ${INPUT_PORT} ${INPUT_USER}@${INPUT_HOST} "docker info"`.catch(() =>
    console.log(chalk.red("Error: Unable to retrieve Docker info"))
);

// Configure Docker Context
console.log(chalk.cyan("Configuring Docker context..."));
const existingContext = await $`docker context ls --format '{{.Name}}' | grep remote`.catch(() => "");
if (existingContext) {
    console.log(chalk.cyan("Removing existing Docker context..."));
    await $`docker context use default`;
    await $`docker context rm remote --force`;
}

console.log(chalk.cyan("Creating Docker context...", `host=ssh://${INPUT_USER}@${INPUT_HOST}:${INPUT_PORT}`));
await $`docker context create remote --docker "host=ssh://${INPUT_USER}@${INPUT_HOST}:${INPUT_PORT}"`;
await $`docker context use remote`;

// Load environment variables if specified
if (INPUT_ENV_FILE) {
    console.log(chalk.cyan(`Sourcing environment file: ${INPUT_ENV_FILE}`));
    await $`source ${INPUT_ENV_FILE}`;
}

if (INPUT_ENV) {
    console.log(chalk.cyan("Setting environment variables..."));
    await $`echo "${INPUT_ENV}" > /tmp/env`;
    await $`source /tmp/env`;
}

// Deploy Docker stack
console.log(chalk.magentaBright(`Deploying Docker Stack: ${INPUT_NAME}`));
await $`docker compose -f "${INPUT_FILE}" up -d --build`;
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');
const runner = fs.readFileSync(path.join(__dirname, 'run-experiment-1-4-before.ps1'), 'utf8');
const wrapper = fs.readFileSync(path.join(__dirname, 'run-experiment-1-6-ai-latency.ps1'), 'utf8');

function assertIncludes(text, value) {
  if (!text.includes(value)) throw new Error(`missing expected source: ${value}`);
}

assertIncludes(runner, '[ValidateRange(0, 60000)][int]$AiDelayMs = 2000');
assertIncludes(runner, '-ActiveMissions 20 -AiDelayMs $AiDelayMs');
assertIncludes(runner, '-ActiveMissions 200 -AiDelayMs $AiDelayMs');
if (runner.includes('-AiDelayMs 2000')) throw new Error('hard-coded AI delay remains in base runner');
assertIncludes(wrapper, '[ValidateSet(500, 1000)][int]$AiDelayMs');
assertIncludes(wrapper, 'docker-compose.experiment-1-4-before.yaml');
assertIncludes(wrapper, '-AiDelayMs $AiDelayMs');
for (const forbidden of ['DOENG_AI_ADMISSION_MAX_CONCURRENT', 'ActiveMissions 250', 'StorageDelayMs 500', 'RequestTimeoutMs 500']) {
  if (wrapper.includes(forbidden)) throw new Error(`wrapper changes frozen variable: ${forbidden}`);
}
console.log('Experiment 1-6 AI latency runner source contract test passed');

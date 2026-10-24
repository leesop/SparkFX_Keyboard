// Development only: npm install @tensorflow/tfjs@4.22.0 in an external working folder.
// NODE_PATH=<that folder>/node_modules node Tools/neural-reference.cjs
// Uses TensorFlow's CPU LSTM to independently check the native Swift implementation.
const tf = require('@tensorflow/tfjs');
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
function load(name) {
  const dir = path.join(root, 'Resources/Models', name);
  const vars = {};
  for (const group of JSON.parse(fs.readFileSync(path.join(dir, 'weights_manifest.json')))) {
    const bytes = Buffer.concat(group.paths.map(p => fs.readFileSync(path.join(dir, p))));
    let offset = 0;
    for (const w of group.weights) {
      const count = w.shape.reduce((a, b) => a * b, 1);
      const values = new Float32Array(count);
      for (let i = 0; i < count; i++) values[i] = bytes.readFloatLE(offset + i * 4);
      vars[w.name] = tf.tensor(values, w.shape);
      offset += count * 4;
    }
  }
  return vars;
}
function state(layers, size) {
  return Array.from({length: layers}, () => [tf.zeros([1, size]), tf.zeros([1, size])]);
}
function runLSTM(input, vars, states, prefix) {
  for (let i = 0; i < states.length; i++) {
    const [c, h] = tf.basicLSTMCell(tf.scalar(1), vars[prefix(i) + 'kernel'],
      vars[prefix(i) + 'bias'], input, states[i][0], states[i][1]);
    states[i][0].dispose(); states[i][1].dispose();
    states[i] = [c, h]; input = h;
  }
  return input;
}
async function main() {
  await tf.setBackend('cpu'); await tf.ready();
  const pg = load('piano-genie'), rnn = load('music-rnn');
  const ps = state(2, 128), rs = state(3, 256);
  const result = {generator: '@tensorflow/tfjs 4.22.0 CPU basicLSTMCell, forgetBias=1', piano: [], rnn: [], drums: []};
  let previous = -1;
  for (const [button, delta, accepted] of [[0,10,39], [7,0.12,44], [2,0.4,48], [5,0.08,41]]) {
    const feat = new Float32Array(123);
    feat[0] = 2 * button / 7 - 1;
    feat[1 + previous + 1] = 1;
    feat[90 + Math.min(32, Math.round(delta * 31.25))] = 1;
    const prefix = 'phero_model/decoder/';
    let input = tf.tensor2d(feat, [1,123]).matMul(pg[prefix+'rnn_input/dense/kernel']).add(pg[prefix+'rnn_input/dense/bias']);
    let h = runLSTM(input, pg, ps, i => prefix+`rnn/rnn/multi_rnn_cell/cell_${i}/lstm_cell/`);
    let logits = h.matMul(pg[prefix+'pitches/dense/kernel']).add(pg[prefix+'pitches/dense/bias']);
    result.piano.push({button, delta, accepted, logits: Array.from(logits.dataSync())});
    previous = accepted;
  }
  for (const [event, rootNote, minor] of [[14,0,false], [0,9,true], [1,5,false], [21,7,false]]) {
    const feat = new Float32Array(75);
    feat[1 + rootNote] = 1;
    for (const pitch of [rootNote,(rootNote+(minor?3:4))%12,(rootNote+7)%12]) feat[13+pitch] = 1;
    feat[25+rootNote] = 1; feat[37+event] = 1;
    let h = runLSTM(tf.tensor2d(feat,[1,75]), rnn, rs, i => `rnn/multi_rnn_cell/cell_${i}/basic_lstm_cell/`);
    let logits = h.matMul(rnn['fully_connected/weights']).add(rnn['fully_connected/biases']);
    result.rnn.push({event, root:rootNote, minor, logits:Array.from(logits.dataSync())});
  }
  // Upstream AttentionWrapper: conv2d over a 32-step output history, query from
  // interleaved c/h states, no attention/bias addition, and six counter bits.
  const drums = load('drums-rnn'), ds = state(3,256);
  const dp = 'rnn/attention_cell_wrapper/';
  let history = tf.zeros([1,32,256]), attention = tf.zeros([1,256]);
  const pattern = [5,0,4,0,6,0,4,0,5,0,4,1,6,0,4,0];
  for (let step = 0; step < 70; step++) {
    const event = pattern[step % 16];
    const feat = new Float32Array(518); feat[event] = 1;
    for (let bit=0; bit<6; bit++) feat[512+bit] = ((step+1)>>bit)&1 ? 1 : -1;
    const input = tf.concat([tf.tensor2d(feat,[1,518]),attention],1)
      .matMul(drums[dp+'kernel']).add(drums[dp+'bias']);
    const h = runLSTM(input, drums, ds, i => dp+`multi_rnn_cell/cell_${i}/basic_lstm_cell/`);
    const features = tf.conv2d(history.reshape([1,32,1,256]),drums[dp+'attention/attn_w'],[1,1],'same');
    const query = tf.concat(ds.flatMap(s => [s[0],s[1]]),1)
      .matMul(drums[dp+'attention/kernel']).reshape([1,1,1,256]);
    const scores = tf.tanh(features.add(query)).mul(drums[dp+'attention/attn_v']).sum([2,3]);
    const weights = tf.softmax(scores).reshape([1,32,1]);
    attention = history.mul(weights).sum(1);
    const output = tf.concat([h,attention],1).matMul(drums[dp+'attention_output_projection/kernel'])
      .add(drums[dp+'attention_output_projection/bias']);
    history = tf.concat([history.slice([0,1,0],[1,31,256]),output.reshape([1,1,256])],1);
    const logits = output.matMul(drums['fully_connected/weights']).add(drums['fully_connected/biases']);
    result.drums.push({event, logits: [0,1,15,31,32,63,64,69].includes(step) ? Array.from(logits.dataSync()) : null});
  }
  fs.writeFileSync(path.join(root,'Tests/NeuralReference.json'), JSON.stringify(result,null,2)+'\n');
  console.log('Wrote numerical reference for all three trained models, including attention/counter rollover.');
}
main().catch(e => { console.error(e); process.exitCode = 1; });

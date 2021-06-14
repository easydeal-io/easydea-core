const { deploySwitch } = require('../truffle-config.js');

const ESDContext = artifacts.require('ESDContext');
const ESDUser = artifacts.require('ESDUser');   
const ESDInfo = artifacts.require('ESDInfo');
const SignReward = artifacts.require('SignReward');

const ESDToken = artifacts.require('ESDToken');
const Multicall = artifacts.require('Multicall');

module.exports = async function(deployer, network, accounts) {
  
  if (deploySwitch.ESDToken) {
    console.log('====================================================');
    console.log('network type: ' + network);
    console.log('Deploy time: ' + new Date().toLocaleString());
    console.log('Deploy type: ESDToken');

    await deployer.deploy(ESDToken);
  }
  console.log('ESDToken Address: ', ESDToken.address);

  if (deploySwitch.ESDUser) {
    console.log('====================================================');
    console.log('network type: ' + network);
    console.log('Deploy time: ' + new Date().toLocaleString());
    console.log('Deploy type: ESDUser');

    await deployer.deploy(ESDUser, ESDToken.address);
  }
  console.log('ESDUser Address: ', ESDUser.address);

  if (deploySwitch.ESDInfo) {
    console.log('====================================================');
    console.log('network type: ' + network);
    console.log('Deploy time: ' + new Date().toLocaleString());
    console.log('Deploy type: ESDInfo');

    await deployer.deploy(ESDInfo, ESDToken.address);
  }
  console.log('ESDInfo Address: ', ESDInfo.address);

  if (deploySwitch.SignReward) {
    console.log('====================================================');
    console.log('network type: ' + network);
    console.log('Deploy time: ' + new Date().toLocaleString());
    console.log('Deploy type: SignReward');

    await deployer.deploy(SignReward, ESDToken.address);
  }
  console.log('SignReward Address: ', SignReward.address);

  if (deploySwitch.Multicall) {
    console.log('====================================================');
    console.log('network type: ' + network);
    console.log('Deploy time: ' + new Date().toLocaleString());
    console.log('Deploy type: Multicall');

    await deployer.deploy(Multicall);
  }
  console.log('Multicall Address: ', Multicall.address);

  console.log('====================================================');
  console.log('network type: ' + network);
  console.log('Deploy time: ' + new Date().toLocaleString());
  console.log('Deploy type: ESDContext');

  await deployer.deploy(ESDContext, ESDUser.address, ESDInfo.address);
  console.log('ESDContext Address:', ESDContext.address);

  console.log('====================================================');
  console.log('network type: ' + network);
  console.log('Time: ' + new Date().toLocaleString());
  console.log('Submit tx to update ESDUser context...');
  const ESDUserInstance = await ESDUser.at(ESDUser.address);
  let tx = await ESDUserInstance.updateContext(ESDContext.address);
  console.log(`tx: ${tx}`);
  console.log('====================================================');
  console.log('Submit tx to update ESDInfo context...');
  const ESDInfoInstance = await ESDInfo.at(ESDInfo.address);
  tx = await ESDInfoInstance.updateContext(ESDContext.address);
  console.log(`tx: ${tx}`);
  console.log('====================================================');
  console.log('Submit tx to update SignReward context...');
  const SignRewardInstance = await SignReward.at(SignReward.address);
  tx = await SignRewardInstance.updateContext(ESDContext.address);
  console.log(`tx: ${tx}`);
};
const { deploySwitch } = require('../truffle-config.js');

const ESDToken = artifacts.require('ESDToken');
const Easydeal = artifacts.require('Easydeal');

const SignReward = artifacts.require('SignReward');
const Multicall = artifacts.require('Multicall');

module.exports = async function(deployer, network, accounts) {

  if (deploySwitch.ESDToken) {
    console.log('====================================================');
    console.log('network type: ' + network);
    console.log('Deploy time: ' + new Date().toLocaleString());
    console.log('Deploy type: ESDToken');

    await deployer.deploy(ESDToken);
    console.log('ESDToken Address: ', ESDToken.address);
  }

  if (deploySwitch.Easydeal) {
    console.log('====================================================');
    console.log('network type: ' + network);
    console.log('Deploy time: ' + new Date().toLocaleString());
    console.log('Deploy type: Easydeal');

    await deployer.deploy(Easydeal, ESDToken.address);
    console.log('Easydeal Address: ', Easydeal.address);
  }

  if (deploySwitch.SignReward) {
    console.log('====================================================');
    console.log('network type: ' + network);
    console.log('Deploy time: ' + new Date().toLocaleString());
    console.log('Deploy type: SignReward');

    await deployer.deploy(SignReward, Easydeal.address, ESDToken.address);
    console.log('SignReward Address:', SignReward.address);
  }

  if (deploySwitch.Multicall) {
    console.log('====================================================');
    console.log('network type: ' + network);
    console.log('Deploy time: ' + new Date().toLocaleString());
    console.log('Deploy type: Multicall');

    await deployer.deploy(Multicall);
    console.log('Multicall Address:', Multicall.address);
  }


};
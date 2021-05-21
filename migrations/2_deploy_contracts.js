const { deploySwitch } = require('../truffle-config.js');

const tokenAddress = '0xf471d89a56c94B5a87498E15861c08d846E937f5';

const Council = artifacts.require('EasydealCouncil');
const Info = artifacts.require('EasydealInfo');
const User = artifacts.require('EasydealUser');

const SignReward = artifacts.require('SignReward');
const Multicall = artifacts.require('Multicall');

module.exports = async function(deployer, network, accounts) {

  if (deploySwitch.Council) {
    console.log('====================================================');
    console.log('network type: ' + network);
    console.log('Deploy time: ' + new Date().toLocaleString());
    console.log('Deploy type: Council');

    await deployer.deploy(Council, tokenAddress);
    console.log('Council Address: ', Council.address);
  }

  if (deploySwitch.Info) {
    console.log('====================================================');
    console.log('network type: ' + network);
    console.log('Deploy time: ' + new Date().toLocaleString());
    console.log('Deploy type: Info');

    await deployer.deploy(Info, Council.address);
    console.log('Info Address: ', Info.address);
  }

  if (deploySwitch.User) {
    console.log('====================================================');
    console.log('network type: ' + network);
    console.log('Deploy time: ' + new Date().toLocaleString());
    console.log('Deploy type: User');

    await deployer.deploy(User, Council.address);
    console.log('User Address: ', User.address);
  }

  if (deploySwitch.SignReward) {
    console.log('====================================================');
    console.log('network type: ' + network);
    console.log('Deploy time: ' + new Date().toLocaleString());
    console.log('Deploy type: SignReward');

    await deployer.deploy(SignReward, User.address, tokenAddress);
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
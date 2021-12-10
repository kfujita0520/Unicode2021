// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

const hre = require("hardhat");
const {ethers, utils} = require("ethers");
//import { BigNumber, utils } from 'ethers';
//import { keccak256, defaultAbiCoder, toUtf8Bytes, solidityPack } from 'ethers/utils';
const {FeeAmount, MaxUint256} = require("@uniswap/v3-sdk");
const { ecsign } = require('ethereumjs-util');
const PERMIT_TYPEHASH = '0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9';
// keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

let UniFactoryV2;
let UniRouterV2;
let Quoter;
let UniFactoryV3;
let UniRouterV3;

let WETH;
let UNI;

let sender;
let privateKey;

async function main() {
    // Hardhat always runs the compile task when running scripts with its command
    // line interface.
    //
    // If this script is run directly using `node` you may want to call compile
    // manually to make sure everything is compiled
    // await hre.run('compile');


    await initializeConstValues();

    const PermitTokenContract = await hre.ethers.getContractFactory("PermitTokenTest");
    const permitToken = await PermitTokenContract.deploy();
    await permitToken.deployed();
    console.log("arbitrageTest deployed to:", permitToken.address);



    let weth_balance = await WETH.balanceOf(sender.address);
    let eth_balance = await sender.getBalance();
    let uni_balance = await UNI.balanceOf(sender.address);
    console.log('Sender Address: ' + sender.address);
    console.log('ETH Balance: ' + eth_balance);
    console.log('UNI Balance: ' + uni_balance);

    console.log(sender.address);
    let name = await UNI.name();
    console.log(name);
    const nonce = await UNI.nonces(sender.address);
    const digest = await getApprovalDigest(
        UNI,
        { owner: sender.address, spender: permitToken.address, value: 100000000000 },
        nonce,
        hre.ethers.constants.MaxUint256
    )

    console.log(digest);

    const { v, r, s } = ecsign(Buffer.from(digest.slice(2), 'hex'), Buffer.from(privateKey.slice(2), 'hex'))


    //await swapETHtoUni();
    await permitToken.transferTest(UNI.address, 100000000000, v, r, s);
    //await permitToken.testPermit(sender.address, 100000000000, v, r, s);


    weth_balance = await WETH.balanceOf(sender.address);
    eth_balance = await sender.getBalance();
    uni_balance = await UNI.balanceOf(sender.address);
    console.log('ETH Balance: ' + eth_balance);
    console.log('UNI Balance: ' + uni_balance);



}

async function initializeConstValues(){
    // We get the contract to deploy
    UniFactoryV2 = await hre.ethers.getContractAt("IUniswapV2Factory", "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f");
    UniRouterV2 = await hre.ethers.getContractAt("IUniswapV2Router02", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D");
    Quoter = await hre.ethers.getContractAt("IQuoter", "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6");
    UniFactoryV3 = await hre.ethers.getContractAt("IUniswapV3Factory", "0x1F98431c8aD98523631AE4a59f267346ea31F984");
    UniRouterV3 = await hre.ethers.getContractAt("ISwapRouter", "0xE592427A0AEce92De3Edee1F18E0157C05861564");

    WETH = await hre.ethers.getContractAt("IWETH", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
    UNI = await hre.ethers.getContractAt("IUniswapV2ERC20", "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984");

    [sender] = await hre.ethers.getSigners();
    privateKey = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
}

async function swapETHtoUni(){
    let eth_amount = 210000000;
    let addresses = [WETH.address, UNI.address];
    let tx = await UniRouterV2.swapExactETHForTokens(0, addresses, sender.address, Date.now() + 1000000, {from: sender.address, value: eth_amount}).catch(err => {
        console.log(err);
    });
    await tx.wait();
}

function getDomainSeparator(name, tokenAddress) {
    return utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(
            ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
            [
                ethers.utils.keccak256(ethers.utils.toUtf8Bytes('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')),
                ethers.utils.keccak256(ethers.utils.toUtf8Bytes(name)),
                ethers.utils.keccak256(ethers.utils.toUtf8Bytes('1')),
                31337,
                tokenAddress
            ]
        )
    )
}

async function getApprovalDigest(
    token,
    approve,
    // approve:{
    //     owner,
    //     spender,
    //     value
    // },
    nonce,
    deadline
) {
    const name = await token.name();
    const DOMAIN_SEPARATOR = getDomainSeparator(name, token.address);
    console.log('DOMAIN: ', DOMAIN_SEPARATOR);
    console.log(approve.owner);
    console.log(approve.spender);
    return ethers.utils.keccak256(
        ethers.utils.solidityPack(
            ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
            [
                '0x19',
                '0x01',
                DOMAIN_SEPARATOR,
                ethers.utils.keccak256(
                    ethers.utils.defaultAbiCoder.encode(
                        ['bytes32', 'address', 'address', 'uint256', 'uint256', 'uint256'],
                        [PERMIT_TYPEHASH, approve.owner, approve.spender, approve.value, nonce, deadline]
                    )
                )
            ]
        )
    )
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

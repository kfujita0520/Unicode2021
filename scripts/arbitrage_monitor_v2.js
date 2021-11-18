// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const {BigNumber} = require("ethers");

let UniFactoryV2;
let WETH;
let BAT;
let ERC20;
let UniRouterV2;
let Quoter;
let UniRouterV3;
let eth_amount;



async function main() {
    // Hardhat always runs the compile task when running scripts with its command
    // line interface.
    //
    // If this script is run directly using `node` you may want to call compile
    // manually to make sure everything is compiled
    // await hre.run('compile');

    // We get the contract to deploy
    UniFactoryV2 = await hre.ethers.getContractAt("IUniswapV2Factory", "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f");
    WETH = await hre.ethers.getContractAt("IWETH", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
    BAT = await hre.ethers.getContractAt("IERC20", "0x0D8775F648430679A709E98d2b0Cb6250d2887EF");
    ERC20 = await hre.ethers.getContractAt("IERC20", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
    UniRouterV2 = await hre.ethers.getContractAt("IUniswapV2Router02", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D");
    Quoter = await hre.ethers.getContractAt("IQuoter", "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6");
    UniRouterV3 = await hre.ethers.getContractAt("ISwapRouter", "0xE592427A0AEce92De3Edee1F18E0157C05861564");

    eth_amount = 100000000;


    const [sender, sender2, sender3] = await hre.ethers.getSigners();
    console.log(sender.address);
    console.log(sender2.address);
    console.log(sender3.address);

    //TODO this initialization should be done, only if arbitrage opportunity comes up.
    const ArbitrageContract = await hre.ethers.getContractFactory("Arbitrage");
    const arbitrage = await ArbitrageContract.deploy(UniFactoryV2.address, UniRouterV3.address);
    await arbitrage.deployed();
    console.log("arbitrage deployed to:", arbitrage.address);


    let profit = await checkV2toV3();
    if(profit < 0){
        console.log('V2toV3: ' + profit);
        let addresses = [WETH.address, BAT.address];
        let amounts = await UniRouterV2.getAmountsOut(eth_amount, addresses).catch(err => {
            console.log(err);
        });
        console.log('BAT V2: ' + amounts[1]);
        let gasCost = await arbitrage.estimateGas.arbitrageV2ToV3(WETH.address, BAT.address, 100000000, 603821239782);
        console.log('Gas Cost: ' + gasCost);
        let gas_price = await hre.ethers.provider.getGasPrice();
        console.log('Gas Price: ' + gas_price);
        let gas_fee = gasCost.mul(gas_price);
        console.log('Gas Fee: ' + gas_fee);
        if(gas_fee > profit){
            console.log('Not enough profit');
        }
    }

    profit = await checkV3toV2();
    if(profit > 0){
        console.log('V3toV2: ' + profit);
        //TODO implement V3toV2 flash swap logic
    }









}

async function checkV2toV3(){
    let addresses = [WETH.address, BAT.address];

    let amounts = await UniRouterV2.getAmountsOut(eth_amount, addresses).catch(err => {
        console.log(err);
    });
    console.log('ETH V2: ' + amounts[0]);
    console.log('BAT V2: ' + amounts[1]);

    let eth_returned_amount = await Quoter.callStatic.quoteExactInputSingle(BAT.address, WETH.address, 3000, amounts[1], 0).catch(err => {
        console.log(err);
    });
    console.log('ETH V3: ' + BigNumber.from(eth_returned_amount).toNumber());
    console.log('ETH V3: ' + eth_returned_amount);
    return eth_returned_amount - eth_amount;
    // if(eth_returned_amount > eth_amount){
    //     console.log('arbitrage opportunity');
    //     return true;
    // } else{
    //     console.log('no arbitrage');
    //     return false;
    // }

}

async function checkV3toV2(){

    let bat_amount = await Quoter.callStatic.quoteExactInputSingle(WETH.address, BAT.address, 3000, eth_amount, 0).catch(err => {
        console.log(err);
    });

    console.log('ETH V3: ' + eth_amount);
    console.log('BAT V3: ' + bat_amount);

    let addresses = [BAT.address, WETH.address];
    let amounts = await UniRouterV2.getAmountsOut(bat_amount, addresses).catch(err => {
        console.log(err);
    });

    let eth_returned_amount = amounts[1];

    console.log('ETH V3: ' + eth_returned_amount);
    return eth_returned_amount - eth_amount;
    // if(eth_returned_amount > eth_amount){
    //     console.log('arbitrage opportunity');
    //     return true;
    // } else{
    //     console.log('no arbitrage');
    //     return false;
    // }

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

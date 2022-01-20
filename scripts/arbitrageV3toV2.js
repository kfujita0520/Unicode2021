// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const {ethers, BigNumber} = require("ethers");



async function main() {
    // Hardhat always runs the compile task when running scripts with its command
    // line interface.
    //
    // If this script is run directly using `node` you may want to call compile
    // manually to make sure everything is compiled
    // await hre.run('compile');

    // We get the contract to deploy
    const UniFactoryV2 = await hre.ethers.getContractAt("IUniswapV2Factory", "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f");
    const WETH = await hre.ethers.getContractAt("IWETH", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
    const BAT = await hre.ethers.getContractAt("IERC20", "0x0D8775F648430679A709E98d2b0Cb6250d2887EF");
    const UNI = await hre.ethers.getContractAt("IUniswapV2ERC20", "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984");
    const UniRouterV2 = await hre.ethers.getContractAt("IUniswapV2Router02", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D");
    const Quoter = await hre.ethers.getContractAt("IQuoter", "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6");
    const UniFactoryV3 = await hre.ethers.getContractAt("IUniswapV3Factory", "0x1F98431c8aD98523631AE4a59f267346ea31F984");
    const UniRouterV3 = await hre.ethers.getContractAt("ISwapRouter", "0xE592427A0AEce92De3Edee1F18E0157C05861564");


    const [sender] = await hre.ethers.getSigners();

    const ArbitrageV3toV2Contract = await hre.ethers.getContractFactory("ArbitrageV3toV2");
    const arbitrage = await ArbitrageV3toV2Contract.deploy(UniFactoryV2.address, UniRouterV3.address);
    console.log("ArbitrageV3toV2 deployed to:", arbitrage.address);


    let weth_balance = await WETH.balanceOf(sender.address);
    let eth_balance = await sender.getBalance();
    let uni_balance = await UNI.balanceOf(sender.address);

    console.log('Sender Address: ' + sender.address);
    console.log('ETH Balance: ' + eth_balance);
    console.log('WETH Balance: ' + weth_balance);
    console.log('UNI Balance: ' + uni_balance);

    // change ETH to WETH first.
    //await WETH.deposit({from: sender.address, value: BigInt(500000000000000000)});
    await WETH.approve(arbitrage.address, hre.ethers.constants.MaxUint256)
    await UNI.approve(arbitrage.address, hre.ethers.constants.MaxUint256)

    //await arbitrage.tokenSwapV3(UNI.address, 1100000);
    await arbitrage.arbitrageV3ToV2(UNI.address, 500000);


    weth_balance = await WETH.balanceOf(sender.address);
    eth_balance = await sender.getBalance();
    uni_balance = await UNI.balanceOf(sender.address);
    console.log('ETH Balance: ' + eth_balance);
    console.log('WETH Balance: ' + weth_balance);
    console.log('UNI Balance: ' + uni_balance);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

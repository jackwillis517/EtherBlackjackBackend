const hre = require("hardhat");
const testnetConfigs = require("../testnets.config");
const fs = require("fs/promises");

async function main() {
  let VRFCoordinatorV2Mock;
  let subscriptionId;
  let vrfCoordinatorAddress;

  const chainId = hre.network.config.chainId;
  const isLocalHostNetwork = chainId == 31337;

  // If this is a local hardhat network, deploy Mock VRF Coordinator first.
  // Initialize variables used throughout this function.
  if (isLocalHostNetwork) {
    console.log("Local blockchain network detected.  Deploying Mock.");
    const BASE_FEE = "100000000000000000";
    const GAS_PRICE_LINK = "1000000000"; // 0.000000001 LINK per gas
    const FUND_AMOUNT = "1000000000000000000"; // 1 eth.

    const VRFCoordinatorV2MockFactory = await hre.ethers.getContractFactory(
      "VRFCoordinatorV2Mock"
    );
    VRFCoordinatorV2Mock = await VRFCoordinatorV2MockFactory.deploy(
      BASE_FEE,
      GAS_PRICE_LINK
    );
    vrfCoordinatorAddress = VRFCoordinatorV2Mock.address;

    // Create VRF Subscription
    const transaction = await VRFCoordinatorV2Mock.createSubscription();
    const transactionReceipt = await transaction.wait(1);
    subscriptionId = ethers.BigNumber.from(
      transactionReceipt.events[0].topics[1]
    );

    // Fund VRF Subscription
    await VRFCoordinatorV2Mock.fundSubscription(subscriptionId, FUND_AMOUNT);

    console.log(
      `Subscription id ${subscriptionId} funded with ${FUND_AMOUNT} wei.`
    );
  } else {
    subscriptionId = testnetConfigs[chainId].subscriptionId;
    vrfCoordinatorAddress = testnetConfigs[chainId].coordinatorAddress;
  }

  if (!subscriptionId || !vrfCoordinatorAddress) {
    throw new Error("Missing configs for non localhost testnet");
  }

  console.log(`Deploying Blackjack to ${hre.network.name}...`);

  const Blackjack = await hre.ethers.getContractFactory("Blackjack");
  const blackjack = await Blackjack.deploy(
    subscriptionId,
    vrfCoordinatorAddress
  );

  const waitBlockConfirmations = isLocalHostNetwork ? 1 : 3;
  await blackjack.deployTransaction.wait(waitBlockConfirmations);

  console.log(
    `Blackjack deployed to ${blackjack.address} on ${hre.network.name}`
  );

  await writeContractDeploymentInfo(blackjack, "BlackjackInfo.json");

  // Register the deployed Fortune Teller as a VRF Consumer on the Mock.
  if (isLocalHostNetwork) {
    VRFCoordinatorV2Mock.addConsumer(subscriptionId, blackjack.address);
  }
}

async function writeContractDeploymentInfo(contract, filename = "") {
  const data = {
    network: hre.network.name,
    contract: {
      address: contract.address,
      signerAddress: contract.signer.address,
      abi: contract.interface.format(),
    },
  };

  const info = JSON.stringify(data, null, 2);
  await fs.writeFile(filename, info, { encoding: "utf-8" });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EXEC404} from "src/EXEC404.sol";

contract DeployScript is Script {

    // Test addresses for merkle tree testing
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private carol = makeAddr("carol");
    address private dave = makeAddr("dave");
    address private emma = makeAddr("emma");
    address private frank = makeAddr("frank");
    address private grace = makeAddr("grace");
    address private henry = makeAddr("henry");
    address private ivy = makeAddr("ivy");
    address private jack = makeAddr("jack");
    address private kelly = makeAddr("kelly");
    address private larry = makeAddr("larry");

    // Optional: Create an array for easier iteration
    address[] private testUsers = [alice, bob, carol, dave, emma, frank, grace, henry, ivy, jack, kelly, larry];
    // Mapping to store all merkle trees data
    mapping(uint256 => mapping(address => bool)) public whitelistsByDay;

    function generateMerkleRoots() private view returns (bytes32[] memory) {
        bytes32[] memory roots = new bytes32[](12); // 12 roots (days 0-11)
        
        for (uint256 day = 0; day < 12; day++) {
            // Count whitelisted addresses for this day
            uint256 leafCount = 0;
            for (uint256 i = 0; i < testUsers.length; i++) {
                if (whitelistsByDay[day][testUsers[i]]) {
                    leafCount++;
                }
            }
            
            // Create leaves array for this day
            bytes32[] memory leaves = new bytes32[](leafCount);
            uint256 leafIndex = 0;
            
            // Generate leaves for whitelisted addresses
            for (uint256 i = 0; i < testUsers.length; i++) {
                if (whitelistsByDay[day][testUsers[i]]) {
                    leaves[leafIndex] = keccak256(abi.encodePacked(testUsers[i]));
                    leafIndex++;
                }
            }
            
            // Sort leaves for consistent tree generation
            sortBytes32Array(leaves);
            
            // Generate and store root for this day
            roots[day] = generateMerkleRoot(leaves);
        }
        
        return roots;
    }

    function sortBytes32Array(bytes32[] memory arr) private pure returns (bytes32[] memory) {
        // Bubble sort implementation (simple but not optimal for large arrays)
        for (uint256 i = 0; i < arr.length - 1; i++) {
            for (uint256 j = 0; j < arr.length - i - 1; j++) {
                if (arr[j] > arr[j + 1]) {
                    // Swap elements
                    (arr[j], arr[j + 1]) = (arr[j + 1], arr[j]);
                }
            }
        }
        return arr;
    }

    function generateMerkleRoot(bytes32[] memory leaves) private pure returns (bytes32) {
        require(leaves.length > 0, "Empty leaves");
        
        if (leaves.length == 1) {
            return leaves[0];
        }
        
        // Create new layer with paired hashes
        uint256 layerLength = (leaves.length + 1) / 2;
        bytes32[] memory layer = new bytes32[](layerLength);
        
        for (uint256 i = 0; i < leaves.length; i += 2) {
            if (i + 1 < leaves.length) {
                // Order the pair based on their values to match MerkleProofLib
                bytes32 left = leaves[i];
                bytes32 right = leaves[i + 1];
                if (left > right) {
                    (left, right) = (right, left);
                }
                layer[i/2] = keccak256(abi.encodePacked(left, right));
            } else {
                layer[i/2] = keccak256(abi.encodePacked(leaves[i], leaves[i]));
            }
        }
        
        // Recursively generate root from this layer
        return generateMerkleRoot(layer);
    }
    function setupRoots() internal returns (bytes32[] memory) {
       bytes32[] memory roots = new bytes32[](12);
        //V1 Roots
        // roots[0] = 0x383d484216d93fbbe5a6b58dc16fcda0abb4b5dc25ebbe822686016bda173de8;
        // roots[1] = 0xe9a7d49502aed47050e71c54456a47848d826184b52b703d5f58d51fd369fcf9;
        // roots[2] = 0xd87d9eeb13a7c51bd2ea10c6b3ec1fa5b941515d8f2343979caf747a8ccbbcbe;
        // roots[3] = 0x9c5fd486f6dd94f7d4cefacca2f8a610fca25d6ae3d6927f8bb77616cf1440cf;
        // roots[4] = 0xacb17e4db8fff2b8e7b682710b383f1f91b40c38ce086c362d80c907649d8247;
        // roots[5] = 0xf34783c0de12064f769d2be787a732db82086a672ec72b1d4fdb23cb11a1e134;
        // roots[6] = 0xcef676cc60c92453554df4c8dc41dbf9fdecae37d7dbcacdb921c4ece8e6d4a5;
        // roots[7] = 0xfcc23603efe9745c52e206c5bd308e333d1c4a6ef87b2c83a459572fc43512f3;
        // roots[8] = 0xb57e39d073e19d1ac0d57c992173748d925e0953b3e9d1ede5b1f0653b2a6a35;
        // roots[9] = 0xcb57758264ef8eeb7a060f9b7c8ffdcefcf5f791a686ed8fe17671c84cfdc3f8;
        // roots[10] = 0x6e664b458778d4896e32882a564617964120e8c4f30e0d9d2f1b07a1894d5d0b;
        // roots[11] = 0xc8a4a04d5cb05d354b3279b8092ad0320912674e7c4fe0f92af5accbf606d384;
        //v2 roots no delegation
        // roots[0] = 0x383d484216d93fbbe5a6b58dc16fcda0abb4b5dc25ebbe822686016bda173de8;
        // roots[1] = 0xba4c7683fe9a03ebb8b98aa2f5672f2bbb13f08938df935f5ead42d0641cedec;
        // roots[2] = 0x56273724a5fe98e289169d65d26ab0b41d5086070ab3680f223395fa2e88e0ac;
        // roots[3] = 0xc8407bfa46ff866d4de05f1a8cfb52adadfb145f0b32b6cb46bc3855f388e209;
        // roots[4] = 0x3318b27514a6cfc186d0b5c187eb328b12603d37ded3c69d214b555294714598;
        // roots[5] = 0xe07ab75c7f20829e490bef5971962417d8e118fb690d27afe641422c25976d95;
        // roots[6] = 0xef4cc785c4cb2c95da781f39848239fdf47f762d3a450a0611386b0a49f3c59c;
        // roots[7] = 0x4e34169c0ae4e58c595fc244e9b4dcbb130cd85358c57bfefa875237f0833db2;
        // roots[8] = 0x26df5fc69123c0c8c899d776332602d792c717606be4fb5798a3d337eda1cc39;
        // roots[9] = 0xe8746cad9f4dba5feac1c8ce05f6a9f4eaf0014d252e2eaf872aa1338fe0e17d;
        // roots[10] = 0x088bfbc026984de05dc754bc59278e143c10f6d0316c08dd1494fc7112e961e1;
        // roots[11] = 0x4989e05b0243e27ad49e29ba0858edfdd8eaa5bff24d08468ff99af05d3ba05d;
        //v2 roots with delegation
        roots[0] = 0x383d484216d93fbbe5a6b58dc16fcda0abb4b5dc25ebbe822686016bda173de8;
        roots[1] = 0x3e755dd64a20ad8829a7f6e1a1df65199a80edc6a500ad0539a4363d623d8429;
        roots[2] = 0xe80a9245200ccbb7e5b8db4a18e354b19574011806e9aac4b3f048c7aa5e281b;
        roots[3] = 0x1dd1fb00acb2042a46ad691a058ec2cdf6e11cb401bb907f10c49071daec8e3d;
        roots[4] = 0x3721ea94d93df2cc9785ffbb0bde71c3495747976119135bcb808b9fd2b148a9;
        roots[5] = 0xc219477ca23adcb4650364be87505596afec465e1320d1fbc534ce6837764349;
        roots[6] = 0xff275b7b05a174b48b33d14bfeb6ac1a63bf44474054887d2fb40ad3110f4e56;
        roots[7] = 0xf7e95a2d1b84642fbc76572eb7e7be51acc71ffb467c04a82d9363b1d3a5f4ae;
        roots[8] = 0xcd962b225230f743505494ce5befdc43bb95039d9cf9cd85e31ab7998c7752bd;
        roots[9] = 0xea0bd929aa9d311b2eb540ad17f8de71cfd8e517a3b561828c8003834ea712d6;
        roots[10] = 0x67125b79075bb36b2be9c1731becda51087a8010418b21af3183e1cbd50880e0;
        roots[11] = 0xa248a94675ab4dbeed416e131c3cb0f1d7be803c5e914dfbe20fe2216fde7034;
        // fake roots for testing
        // Set up whitelists for each day (0-12) procedurally
        // for (uint256 day = 0; day <= 12; day++) {
        //     // Each day includes users from index 0 up to the current day (inclusive)
        //     for (uint256 userIndex = 0; userIndex <= day && userIndex < testUsers.length; userIndex++) {
        //         whitelistsByDay[day][testUsers[userIndex]] = true;
        //     }
        // }

        // // Generate merkle roots
        // bytes32[] memory roots = generateMerkleRoots();

        return roots;
    }

    function internalDeploy() public returns (EXEC404) {
        bytes32[] memory roots = setupRoots();
        EXEC404 token = new EXEC404(roots);
        return token;
    }

    function run() public returns (EXEC404) {
        bytes32[] memory roots = setupRoots();
        
        vm.startBroadcast();

        EXEC404 token = internalDeploy();

        token.configure(
            "https://monygroupmint.nyc3.digitaloceanspaces.com/cultexecbadges/public/metadata/",
            "https://ms2.fun/EXEC404/public/unrevealed.json",
            true
        );

        vm.stopBroadcast();

        // Verify contract after broadcasting is done
        if (block.chainid == 1) { // Mainnet chain ID
            string[] memory commands = new string[](4);
            commands[0] = "forge";
            commands[1] = "verify-contract";
            commands[2] = vm.toString(address(token));
            commands[3] = "EXEC404";
            vm.ffi(commands);
        }

        return (token);
    }
}
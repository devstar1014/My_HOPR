pragma solidity ^0.5.3;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract PaymentChannel {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public token;        // the token that will be used to settle payments
    uint256 public secsClosure; // seconds it takes to allow closing of channel after channel's -
                                // 'sender' provided a signature

    // the payment channel has been created and opened
    event OpenedChannel(
        address indexed funder,
        address indexed sender,
        address indexed recipient,
        uint256 deposit
    );

    // the payment channel's 'sender' is closing the channel
    event InitiatedChannelClosure(
        address indexed sender,
        address indexed recipient,
        uint256 closureTime
    );

    // the payment channel has been settled and closed
    event ClosedChannel(
        address indexed sender,
        address indexed recipient,
        uint256 senderAmount,
        uint256 recipientAmount
    );

    struct Channel {
        uint256 deposit;        // the token deposit
        uint256 closureTime;    // the time when the channel can be closed by 'sender'
        bool isOpen;            // channel is open
    }

    // store channels e.g: channels[sender][recipient]
    mapping(address => mapping(address => Channel)) public channels;

    constructor(IERC20 _token, uint256 _secsClosure) public {
        token = _token;
        secsClosure = _secsClosure;
    }

    /**
     * Create and open a channel between 'sender' and 'recipient',
     * specified tokens must be approved beforehand.
     *
     * @notice create and open a channel
     * @param funder address account which funds the channel
     * @param sender address account which owns the channel
     * @param recipient address account which receives payments
     * @param amount uint256 amount to fund the channel
     */
    function createChannel(address funder, address sender, address recipient, uint256 amount) external {
        require(funder != address(0), "'funder' address is empty");
        require(sender != address(0), "'sender' address is empty");
        require(recipient != address(0), "'recipient' address is empty");
        require(amount > 0, "'amount' must be larger than 0");

        Channel storage channel = channels[sender][recipient];
        require(channel.isOpen == false, "channel is not closed");

        token.safeTransferFrom(funder, address(this), amount);

        channel.deposit = amount;
        channel.isOpen = true;

        emit OpenedChannel(funder, sender, recipient, amount);
    }

    /**
     * Close a channel between 'sender' and 'recipient',
     * the recipient can close the channel at any time,
     * by presenting a signed amount from the sender.
     * 
     * The recipient will be sent that amount,
     * and the remainder will go back to the sender.
     *
     * @notice close and settle channel
     * @param sender address account which will receive the 'amount'
     * @param amount uint256 amount that the recipient will claim
     * @param signature bytes signature to verify that the recipient can claim tokens
     */
    function closeChannel(address sender, uint256 amount, bytes calldata signature) external {
        Channel storage channel = channels[sender][msg.sender];

        require(
            channel.isOpen ||
            isChannelPendingClosure(channel),
            "channel must be 'open' or 'pending for closure'"
        );
        require(isValidSignature(sender, amount, signature), "signature is not valid");

        settle(sender, msg.sender, amount);
    }

    /**
     * The 'sender' can initiate channel closure at any time,
     * it starts a timeout.
     *
     * @notice initiate channel's closure
     * @param recipient address account which will receive the payment
     */
    function initiateChannelClosure(address recipient) external {
        Channel storage channel = channels[msg.sender][recipient];
        require(channel.isOpen, "channel is not open");

        channel.closureTime = now + secsClosure;

        emit InitiatedChannelClosure(msg.sender, recipient, channel.closureTime);
    }

    /**
     * If the timeout is reached without the recipient providing a signature,
     * then the tokens can be claimed by 'sender'.
     *
     * @notice claim channel's closure
     * @param recipient address account which will receive the 'amount'
     * @param amount uint256 amount that the recipient will claim
     */
    function claimChannelClosure(address recipient, uint256 amount) external {
        Channel storage channel = channels[msg.sender][recipient];

        require(
            channel.isOpen &&
            isChannelPendingClosure(channel),
            "channel is not pending for closure"
        );
        require(now >= channel.closureTime, "'closureTime' has not passed");

        settle(msg.sender, recipient, amount);
    }

    /**
     * Settle channel, send 'amount' to recipient and the rest to sender.
     *
     * @notice settle channel
     * @param sender address account which owns the channel
     * @param recipient address account which receives payments
     * @param amount uint256 amount to fund the channel
     */
    function settle(address sender, address recipient, uint256 amount) internal {
        Channel storage channel = channels[sender][recipient];

        require(amount <= channel.deposit, "'amount' is larger than deposit");

        if (amount > 0) {
            token.safeTransfer(recipient, amount);
            channel.deposit = channel.deposit.sub(amount);
        }

        if (channel.deposit > 0) {
            token.safeTransfer(sender, channel.deposit);
        }

        emit ClosedChannel(sender, recipient, channel.deposit, amount);

        channel.deposit = 0;
        channel.closureTime = 0;
        channel.isOpen = false;
    }

    /// return 'true' if channel is pending for closure
    function isChannelPendingClosure(Channel memory channel) internal pure returns (bool) {
        return channel.closureTime > 0;
    }

    // return 'true' if signaure is signed by 'signer'
    function isValidSignature(address signer, uint256 amount, bytes memory signature)
    internal view returns (bool) {
        bytes32 message = prefixed(keccak256(abi.encodePacked(address(this), amount)));

        return recoverSigner(message, signature) == signer;
    }

    function splitSignature(bytes memory signature) internal pure returns (uint8, bytes32, bytes32) {
        require(signature.length == 65, "signature length is not 65");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(signature, 32))
            // second 32 bytes
            s := mload(add(signature, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(signature, 96)))
        }

        return (v, r, s);
    }

    function recoverSigner(bytes32 message, bytes memory signature) internal pure returns (address) {
        uint8 v;
        bytes32 r;
        bytes32 s;

        (v, r, s) = splitSignature(signature);

        return ecrecover(message, v, r, s);
    }

    // builds a prefixed hash to mimic the behavior of eth_sign
    function prefixed(bytes32 message) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
    }
}
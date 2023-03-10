//"SPDX-License-Identifier: BUSL1.1"
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v2-solidity-utils/contracts/math/Math.sol";

abstract contract Heap {
    
    struct Node {
        uint256 value;
        bytes32 ref;
    }

    Node[] _orderbook;

    // Inserts adds in a value to our heap.
    //_value is price in the orderbook, _ref is order reference
    function insert(uint256 _value, bytes32 _ref) internal {
        // Add the value to the end of our array
        _orderbook.push(Node(_value, _ref));

        // Start at the end of the array
        uint256 currentIndex = Math.sub(_orderbook.length, 1);

        // Bubble up the value until it reaches it's correct place (i.e. it is smaller than it's parent)
        while (
            currentIndex > 0 &&
            _orderbook[Math.div(Math.sub(currentIndex, 0), 2, false)].value < _orderbook[currentIndex].value
        ) {
            // If the parent value is lower than our current value, we swap them
            Node memory temp = _orderbook[Math.div(currentIndex, 2, false)];
            _orderbook[Math.div(currentIndex, 2, false)] = _orderbook[currentIndex];
            _orderbook[currentIndex] = temp;

            // change our current Index to go up to the parent
            currentIndex = Math.div(currentIndex, 2, false);
        }
    }

    // RemoveMax pops off the root element of the heap (the highest value here) and rebalances the heap
    // This function is to be used when we need to find the max buy price for a new sell order 
    function removeMax() internal returns (uint256) {
        // Ensure the heap exists
        require(_orderbook.length > 0, "Orderbook is not initialized");

        // take the root value of the heap
        uint256 toReturn = _orderbook[0].value;

        // Takes the last element of the array and put it at the root
        _orderbook[0] = _orderbook[Math.sub(_orderbook.length, 1)];

        // Delete the last element from the array
        _orderbook.pop();

        // Start at the top
        uint256 currentIndex = 0;

        // Bubble down
        bubbleDown(currentIndex);

        // finally, return the top of the heap
        return toReturn;
    }

    function deleteOrder(uint256 _index) internal {
        // Ensure the heap exists
        require(_orderbook.length > 0, "Orderbook is not initialized");

        _orderbook[_index].value = 0;

        // Bubble down
        bubbleDown(_index);
    }

    // This function is to be used when we need to find the min sell price for a new buy order 
    function removeMin() public returns(uint256){
        uint256 toReturn = _orderbook[Math.sub(_orderbook.length, 1)].value;
        _orderbook.pop();
        return toReturn;
    }

    function bubbleDown(uint256 currentIndex) private {
        while (Math.mul(currentIndex, 2) < Math.sub(_orderbook.length, 1)) {
            // get the current index of the children
            uint256 j = Math.add(Math.mul(currentIndex, 2), 1);

            // left child value
            uint256 leftChild = _orderbook[j].value;
            // right child value
            uint256 rightChild = _orderbook[Math.add(j, 1)].value;

            // Compare the left and right child. if the rightChild is greater, then point j to it's index
            if (leftChild < rightChild) {
                j = Math.add(j, 1);
            }

            // compare the current parent value with the highest child, if the parent is greater, we're done
            if (_orderbook[currentIndex].value > _orderbook[j].value) {
                break;
            }

            // else swap the value
            Node memory tempOrder = _orderbook[currentIndex];
            _orderbook[currentIndex] = _orderbook[j];
            _orderbook[j] = tempOrder;

            // and let's keep going down the heap
            currentIndex = j;
        }
    }

    function getOrderbook() internal view returns (Node[] memory) {
        return _orderbook;
    }

    function getMax() internal view returns (uint256) {
        return _orderbook[0].value;
    }

    function getMin() public view returns (uint256) {
        return _orderbook[Math.sub(_orderbook.length, 1)].value;
    }
}
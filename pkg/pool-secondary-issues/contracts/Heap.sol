//"SPDX-License-Identifier: BUSL1.1"
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v2-solidity-utils/contracts/math/Math.sol";

abstract contract Heap {
    
    struct Node {
        uint256 value;
        bytes32 ref;
    }

    Node[] _buyOrderbook;
    mapping(bytes32 => uint256) private _buyIndex;

    Node[] _sellOrderbook;
    mapping(bytes32 => uint256) private _sellIndex;

    // Inserts a buy order into heap
    // Buy orderbook needs to be a max heap as sellers want the best price
    function insertBuyOrder(uint256 _value, bytes32 _ref) internal {
        // Add the price of the order at the end of the heap
        _buyOrderbook.push(Node(_value, _ref));

        // Start at the end of the heap
        uint256 currentIndex = Math.sub(_buyOrderbook.length, 1);

        // Bubble up the value until it reaches it's correct place (i.e. it is smaller than it's parent)
        uint256 parentIndex = Math.div(currentIndex, 2, false);

        while (
            currentIndex > 0 &&
            _buyOrderbook[parentIndex].value < _buyOrderbook[currentIndex].value
        ) {
            // If the parent value is lower than our current value, we swap them
            Node memory temp = _buyOrderbook[parentIndex];
            _buyOrderbook[parentIndex] = _buyOrderbook[currentIndex];
            _buyIndex[_buyOrderbook[currentIndex].ref] = parentIndex;
            _buyOrderbook[currentIndex] = temp;
            _buyIndex[temp.ref] = currentIndex;

            // change our current Index to go up to the parent
            currentIndex = parentIndex;
            parentIndex = Math.div(currentIndex, 2, false);
        }
    }

    // Inserts a sell order into heap
    // Sell orderbook needs to be a min heap as buyers want the least price
    function insertSellOrder(uint256 _value, bytes32 _ref) internal {
        // Add the price of the order at the end of the heap
        _sellOrderbook.push(Node(_value, _ref));

        // Start at the end of the heap
        uint256 currentIndex = Math.sub(_sellOrderbook.length, 1);

        // Bubble up the value until it reaches it's correct place (i.e. it is larger than it's parent)
        uint256 parentIndex = Math.div(currentIndex, 2, false);

        while (
            currentIndex > 0 &&
            _sellOrderbook[parentIndex].value > _sellOrderbook[currentIndex].value
        ) {
            // If the parent value is larger than our current value, we swap them
            Node memory temp = _sellOrderbook[parentIndex];
            _sellOrderbook[parentIndex] = _sellOrderbook[currentIndex];
            _sellIndex[_sellOrderbook[currentIndex].ref] = parentIndex;
            _sellOrderbook[currentIndex] = temp;
            _sellIndex[temp.ref] = currentIndex;

            // change our current Index to go up to the parent
            currentIndex = parentIndex;
            parentIndex = Math.div(currentIndex, 2, false);
        }
    }

    // removeBuyOrder pops off the root element of the max heap and rebalances the heap
    // This function is to be used when we need to find the max buy price for a new sell order
    function removeBuyOrder() internal returns (bytes32) {
        // Ensure the heap exists
        require(_buyOrderbook.length > 0, "Orderbook is empty");

        // take the root ref of the heap
        bytes32 toReturn = _buyOrderbook[0].ref;

        // Takes the last element of the array and put it at the root
        _buyOrderbook[0] = _buyOrderbook[Math.sub(_buyOrderbook.length, 1)];
        _buyIndex[_buyOrderbook[0].ref] = 0;

        // Delete the last element from the array
        _buyOrderbook.pop();

        // Start at the top
        uint256 currentIndex = 0;

        // Bubble down
        //when we need to find the max buy price for a new sell order
        if(_buyOrderbook.length > 0)
            bubbleDownForMax(currentIndex);

        // finally, return the top of the heap
        return toReturn;
    }

    // removeSellOrder pops off the root element of the min heap and rebalances the heap
    // This function is to be used when we need to find the min sell price for a new buy order
    function removeSellOrder() internal returns (bytes32) {
        // Ensure the heap exists
        require(_sellOrderbook.length > 0, "Orderbook is empty");

        // take the root ref of the heap
        bytes32 toReturn = _sellOrderbook[0].ref;

        // Takes the last element of the array and put it at the root
        _sellOrderbook[0] = _sellOrderbook[Math.sub(_sellOrderbook.length, 1)];
        _sellIndex[_sellOrderbook[0].ref] = 0;

        // Delete the last element from the array
        _sellOrderbook.pop();

        // Start at the top
        uint256 currentIndex = 0;

        // Bubble down
        //when we need to find the min sell price for a new buy order
        if(_sellOrderbook.length > 0)
            bubbleDownForMin(currentIndex);
        
        // finally, return the top of the heap
        return toReturn;
    }

    function bubbleDownForMax(uint256 currentIndex) private {
        while (Math.mul(currentIndex, 2) < Math.sub(_buyOrderbook.length, 1)) {
            // get the current index of the children
            uint256 j = Math.mul(currentIndex, 2);

            // left child value
            uint256 leftChild = _buyOrderbook[j].value;
            // right child value
            uint256 rightChild = _buyOrderbook[Math.add(j, 1)].value;

            // Compare the left and right child. if the rightChild is greater, then point j to it's index
            if (leftChild < rightChild) {
                j = Math.add(j, 1);
            }

            // compare the current parent value with the highest child, if the parent is greater, we're done
            if (_buyOrderbook[currentIndex].value > _buyOrderbook[j].value) {
                break;
            }

            // else swap the value
            Node memory tempOrder = _buyOrderbook[currentIndex];
            _buyOrderbook[currentIndex] = _buyOrderbook[j];
            _buyIndex[_buyOrderbook[j].ref] = currentIndex;
            _buyOrderbook[j] = tempOrder;
            _buyIndex[tempOrder.ref] = j;

            // and let's keep going down the heap
            currentIndex = j;
        }
    }

    function bubbleDownForMin(uint256 currentIndex) private {
        while (Math.mul(currentIndex, 2) < Math.sub(_sellOrderbook.length, 1)) {
            // get the current index of the children
            uint256 j = Math.mul(currentIndex, 2);

            // left child value
            uint256 leftChild = _sellOrderbook[j].value;
            // right child value
            uint256 rightChild = _sellOrderbook[Math.add(j, 1)].value;

            // Compare the left and right child. if the rightChild is lesser, then point j to it's index
            if (leftChild > rightChild) {
                j = Math.add(j, 1);
            }

            // compare the current parent value with the highest child, if the parent is lesser, we're done
            if (_sellOrderbook[currentIndex].value < _sellOrderbook[j].value) {
                break;
            }

            // else swap the value
            Node memory tempOrder = _sellOrderbook[currentIndex];
            _sellOrderbook[currentIndex] = _sellOrderbook[j];
            _sellIndex[_sellOrderbook[j].ref] = currentIndex;
            _sellOrderbook[j] = tempOrder;
            _sellIndex[tempOrder.ref] = j;

            // and let's keep going down the heap
            currentIndex = j;
        }
    }

    function editOrderbook(uint256 price, bytes32 ref, bool buy) internal {
        if(buy){
            _buyOrderbook[_buyIndex[ref]].value = price;
            if(_buyIndex[ref] == 0)
                bubbleDownForMax(0);
        }
        else{
            _sellOrderbook[_sellIndex[ref]].value = price; 
            if(_sellIndex[ref] == 0)
                bubbleDownForMin(0);
        }
    }

    function cancelOrderbook(bytes32 ref, bool buy) internal {
        if(buy){
            if(_buyIndex[ref]==0){
                removeBuyOrder();
            }
            else{
                _buyOrderbook[_buyIndex[ref]] = _buyOrderbook[Math.sub(_buyOrderbook.length, 1)];
                _buyOrderbook.pop();
            }
        }
        else{
            if(_sellIndex[ref]==0){
                removeSellOrder();
            }
            else{
                _sellOrderbook[_sellIndex[ref]] = _sellOrderbook[Math.sub(_sellOrderbook.length, 1)];
                _sellOrderbook.pop();
            }
        }
    }

    function getSellOrderbook() internal view returns (Node[] memory) {
        return _sellOrderbook;
    }

    function getBuyOrderbook() internal view returns (Node[] memory) {
        return _buyOrderbook;
    }

    function getBestSellPrice() internal view returns (uint256) {
        return _sellOrderbook[0].value;
    }

    function getBestBuyPrice() internal view returns (uint256) {
        return _buyOrderbook[0].value;
    }

}
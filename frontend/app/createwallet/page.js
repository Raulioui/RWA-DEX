"use client";
import { useState } from 'react';

export default function CreateAccount() {
  const [accountId, setAccountId] = useState('');
  const [accountIdDetails, setAccountIdDetails] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      const response = await fetch(`https://broker-api.sandbox.alpaca.markets/v1beta/accounts/${accountId}/funding_wallet`, {
        method: 'POST',
        headers: { 
            'Authorization': 'Basic ' + btoa(`${process.env.NEXT_PUBLIC_ALPACA_KEY}:${process.env.NEXT_PUBLIC_ALPACA_SECRET}`)
        },
      });
      const result = await response.json();
      console.log(result);
    } catch (error) {
      alert('Error: ' + error.message);
      console.error('Submit error:', error);
    }
  };

  const retrieveWalletData = async () => {

    try {
      const response = await fetch(`https://broker-api.sandbox.alpaca.markets/v1/accounts/${accountIdDetails}/wallets`, {
        method: 'GET',
        headers: { 
            'Content-Type': 'application/json',
            'Authorization': 'Basic ' + btoa(`${process.env.NEXT_PUBLIC_ALPACA_KEY}:${process.env.NEXT_PUBLIC_ALPACA_SECRET}`)
        },
      });
      const result = await response.json();
      console.log(result);
    } catch (error) {
      alert('Error: ' + error.message);
      console.error('Submit error:', error);
    }
  }

  return (
    <div className="p-8 max-w-lg mx-auto bg-gray-50 bg-black text-white shadow-md rounded-lg text-black">
    <h1 className="text-2xl font-bold text-center mb-6">Create Wallet</h1>
    <form onSubmit={handleSubmit} className="space-y-6 text-black">
      <fieldset>
          <input
            type="text"
            placeholder="Account Id"
            value={accountId}
            onChange={(e) => setAccountId(e.target.value)}
            className="w-full p-3 border rounded-md focus:outline-none focus:ring focus:ring-indigo-200"
            required
          />
      </fieldset>

      <button
        type="submit"
        className="w-full bg-indigo-600 text-white p-3 rounded-md hover:bg-indigo-700"
      >
        Submit
      </button>
    </form>

      <fieldset>
          <input
            type="text"
            placeholder="Account Id"
            value={accountIdDetails}
            onChange={(e) => setAccountIdDetails(e.target.value)}
            className="w-full text-black p-3 border rounded-md focus:outline-none focus:ring focus:ring-indigo-200"
            required
          />
      </fieldset>

      <button
        onClick={retrieveWalletData}
        type="submit"
        className="w-full bg-indigo-600 text-white p-3 rounded-md hover:bg-indigo-700"
      >
        Get details
      </button>
  </div>
  );
}
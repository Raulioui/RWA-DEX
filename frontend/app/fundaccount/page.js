"use client";
import { useState } from 'react';

export default function CreateAccount() {
  const [accountId, setAccountId] = useState('');

  const createACH = async () => {
    const response = await fetch(`https://broker-api.sandbox.alpaca.markets/v1/accounts/${accountId}/ach_relationships`, {
        method: 'POST',
        headers: { 
            'Authorization': 'Basic ' + btoa(`${process.env.NEXT_PUBLIC_ALPACA_KEY}:${process.env.NEXT_PUBLIC_ALPACA_SECRET}`),
            'Content-Type': 'application/json',
            'accept': 'application/json'
        },
        body: JSON.stringify({
            bank_account_type: 'CHECKING',
            account_owner_name: 'Raul Muela',
            bank_account_number: '123456789',
            bank_routing_number: '011000015'
        })
      });
      const res = await response.json();
      console.log(res);
  }

  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      const response = await fetch(`https://broker-api.sandbox.alpaca.markets/v1/accounts/${accountId}/transfers`, {
        method: 'POST',
        headers: { 
            'Authorization': 'Basic ' + btoa(`${process.env.NEXT_PUBLIC_ALPACA_KEY}:${process.env.NEXT_PUBLIC_ALPACA_SECRET}`),
            'Content-Type': 'application/json',
            'accept': 'application/json'
        },
        body: JSON.stringify({
            transfer_type: 'ach',
            direction: 'INCOMING',
            timing: 'immediate',
            amount: '10000',
            relationship_id: 'cb10050a-5a02-4641-abce-351f799a06a9'
        })
      });
      const res = await response.json();
      console.log(res);
    } catch (error) {
      alert('Error: ' + error.message);
      console.error('Submit error:', error);
    }
  };

  return (
    <div className="p-8 max-w-lg mx-auto bg-gray-50 bg-black text-white shadow-md rounded-lg">
    <h1 className="text-2xl font-bold text-center mb-6">Create Account</h1>
    <form onSubmit={handleSubmit} className="space-y-6 text-black">
      <fieldset>
        <legend className="text-lg font-medium">Fund Account</legend>
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
        <legend className="text-lg font-medium">Create ach</legend>
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
        onClick={createACH}
        className="w-full bg-indigo-600 text-white p-3 rounded-md hover:bg-indigo-700"
      >
        Submit
      </button>
  </div>
  );
}
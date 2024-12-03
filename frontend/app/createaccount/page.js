"use client";
import { useState } from 'react';

export default function CreateAccount() {
  const [formData, setFormData] = useState({
    contact: {
      email_address: '',
      phone_number: '',
      street_address: '',
      city: '',
    },
    identity: {
      given_name: '',
      family_name: '',
      date_of_birth: '',
      tax_id: '666-55-4321',
      tax_id_type: 'NATIONAL_ID',
      country_of_tax_residence: '',
      funding_source: [],
    },
    disclosures: {
      "enabled_assets": [
        "crypto"
      ],
      is_control_person: false,
      is_affiliated_exchange_or_finra: false,
      is_politically_exposed: false,
      immediate_family_exposed: false
    },
    agreements: [
        {
            agreement: 'customer_agreement',
            signed_at: '2019-09-11T18:09:33Z',
            ip_address: '185.13.21.99'
        },
        {
          agreement: "crypto_agreement",
          signed_at: "2019-09-11T18:09:33Z",
          ip_address: "185.13.21.99"
        }
    ]
  });

  const handleChange = (e, section, key) => {
    const value =
      e.target.type === 'checkbox' ? e.target.checked : e.target.value;
    setFormData((prev) => ({
      ...prev,
      [section]: {
        ...prev[section],
        [key]: value,
      },
    }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    console.log('Submitting:', formData);
    try {
      const response = await fetch('https://broker-api.sandbox.alpaca.markets/v1/accounts', {
        method: 'POST',
        headers: { 
            'Content-Type': 'application/json',
            'Authorization': 'Basic ' + btoa(`${process.env.NEXT_PUBLIC_ALPACA_KEY}:${process.env.NEXT_PUBLIC_ALPACA_SECRET}`)
        },
        body: JSON.stringify(formData),
      });

      const result = await response.json();
      if (response.ok) {
        try {
          const response = await fetch(`https://broker-api.sandbox.alpaca.markets/v1beta/accounts/${result.id}/funding_wallet`, {
            method: 'POST',
            headers: { 
                'Content-Type': 'application/json',
                'Authorization': 'Basic ' + btoa(`${process.env.NEXT_PUBLIC_ALPACA_KEY}:${process.env.NEXT_PUBLIC_ALPACA_SECRET}`)
            },
          });
    
          const result = await response.json();
          if (response.ok) {
            alert('Wallet created successfully!');
            console.log(result);
          } else {
            alert('Error creating account: ' + (result.error || 'Unknown error'));
            console.error(result);
          }
        } catch (error) {
          alert('Error: ' + error.message);
        }

        console.log(result);
      } else {
        alert('Error creating account: ' + (result.error || 'Unknown error'));
        console.error(result);
      }
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
        <legend className="text-lg font-medium">Contact Information</legend>
        <div className="space-y-4 mt-4">
          <input
            type="email"
            placeholder="Email Address"
            value={formData.contact.email_address}
            onChange={(e) => handleChange(e, 'contact', 'email_address')}
            className="w-full p-3 border rounded-md focus:outline-none focus:ring focus:ring-indigo-200"
            required
          />
          <input
            type="text"
            placeholder="Phone Number"
            value={formData.contact.phone_number}
            onChange={(e) => handleChange(e, 'contact', 'phone_number')}
            className="w-full p-3 border rounded-md focus:outline-none focus:ring focus:ring-indigo-200"
            required
          />
            <input
            type="text"
            placeholder="Street Address"
            value={formData.contact.street_address}
            onChange={(e) => handleChange(e, 'contact', 'street_address')}
            className="w-full p-3 border rounded-md focus:outline-none focus:ring focus:ring-indigo-200"
            required
          />
          <input
            type="text"
            placeholder="City"
            value={formData.contact.city}
            onChange={(e) => handleChange(e, 'contact', 'city')}
            className="w-full p-3 border rounded-md focus:outline-none focus:ring focus:ring-indigo-200"
            required
          />
        </div>
      </fieldset>

      <fieldset>
        <legend className="text-lg font-medium">Identity Information</legend>
        <div className="space-y-4 mt-4">
          <input
            type="text"
            placeholder="Given Name"
            value={formData.identity.given_name}
            onChange={(e) => handleChange(e, 'identity', 'given_name')}
            className="w-full p-3 border rounded-md focus:outline-none focus:ring focus:ring-indigo-200"
            required
          />
          <input
            type="text"
            placeholder="Family Name"
            value={formData.identity.family_name}
            onChange={(e) => handleChange(e, 'identity', 'family_name')}
            className="w-full p-3 border rounded-md focus:outline-none focus:ring focus:ring-indigo-200"
            required
          />
          <input
            type="date"
            value={formData.identity.date_of_birth}
            onChange={(e) => handleChange(e, 'identity', 'date_of_birth')}
            className="w-full p-3 border rounded-md focus:outline-none focus:ring focus:ring-indigo-200"
            required
          />
            <input
            type="text"
            placeholder="Country of Tax Residence"
            value={formData.identity.country_of_tax_residence}
            onChange={(e) =>
              handleChange(e, 'identity', 'country_of_tax_residence')
            }
            className="w-full p-3 border rounded-md focus:outline-none focus:ring focus:ring-indigo-200"
            required
          />
          <div className="mt-4 space-y-2">
            {['investments', 'savings', 'salary', 'inheritance', 'other'].map(
                (source) => (
                <label key={source} className="flex items-center space-x-2">
                    <input
                    type="checkbox"
                    value={source}
                    checked={formData.identity.funding_source.includes(source)}
                    onChange={(e) => {
                        const value = e.target.value;
                        setFormData((prev) => {
                        const updatedFundingSource = [...prev.identity.funding_source];
                        if (e.target.checked) {
                            // Add to array if checked
                            updatedFundingSource.push(value);
                        } else {
                            // Remove from array if unchecked
                            const index = updatedFundingSource.indexOf(value);
                            if (index > -1) {
                            updatedFundingSource.splice(index, 1);
                            }
                        }
                        return {
                            ...prev,
                            identity: {
                            ...prev.identity,
                            funding_source: updatedFundingSource,
                            },
                        };
                        });
                    }}
                    className="focus:ring focus:ring-indigo-200"
                    />
                    <span className="capitalize">{source}</span>
                </label>
                )
            )}
            </div>
          
        </div>
      </fieldset>

      <button
        type="submit"
        className="w-full bg-indigo-600 text-white p-3 rounded-md hover:bg-indigo-700"
      >
        Submit
      </button>
    </form>
  </div>
  );
}
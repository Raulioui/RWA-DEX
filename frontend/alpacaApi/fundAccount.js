const options = {
    method: 'POST',
    headers: {accept: 'application/json', 'content-type': 'application/json'},
    body: JSON.stringify({
      identity: {tax_id_type: 'USA_SSN'},
      disclosures: {
        is_control_person: true,
        is_affiliated_exchange_or_finra: true,
        is_politically_exposed: true,
        immediate_family_exposed: true
      }
    })
  };
  
  fetch('https://broker-api.sandbox.alpaca.markets/v1/accounts', options)
    .then(res => res.json())
    .then(res => console.log(res))
    .catch(err => console.error(err));
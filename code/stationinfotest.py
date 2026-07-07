# Rhode Island station code: B04

import requests
import urllib.request
import os, json, traceback

# Function to get live train data for Rhode Island Ave-Brentwood
def get_train_data():
	try:
		url = "https://api.wmata.com/StationPrediction.svc/json/GetPrediction/B04"

		hdr = {
		# Request headers
			'Cache-Control': 'no-cache',
			'api_key': os.environ.get('WMATAKEY')
		}

		r = requests.get(url, headers=hdr)
		#print("MAYBE")
		#print(r.text)
		#print(r.json())

		# Check if the response is successful
		if r.status_code == 200:
			resp = r.json()
			data = resp["Trains"]
			return data
		else:
			return None

	except Exception as e:
		print(traceback.format_exc())
		print(e)

#def get_train_data():
#    url = "https://api.wmata.com/StationPrediction.svc/json/GetPrediction/B04"
#    response = requests.get(url)

def make_print_string(timesdict):
	outstring = ''
	for k, v in timesdict.items():
		outstring += k + ": "
		for time in v:
			outstring += time + ", "
		outstring += "    "
	return outstring


print(os.environ.get('testenv'))
output_dict = {}
traindata = get_train_data()
if traindata is not None:
	for train in traindata:
		dest = train.get('Destination')
		mins = train.get('Min')
		if output_dict.get(dest):
			output_dict.update({dest: output_dict.get(dest) + [mins]})
		else:
			output_dict.update({dest: [mins]})
		#print(f"{train.get('Destination')}: {train.get('Min')}")
	if output_dict:
		final_string = make_print_string(output_dict)
		print(output_dict)
		print(final_string)

print(f"exit")

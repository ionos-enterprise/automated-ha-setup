def user_as_csv():
	'''
	Retrieve the users from a minion, formatted
	as comma-separated-values (CSV)

	CLI Exmaple:
	
	... code-block:: bash

		salt '*' customuser.users_as_csv
	'''
	user_list = __salt__['user.list_users'] ()
	csv_list = ','.join(user_list)
	return csv_list

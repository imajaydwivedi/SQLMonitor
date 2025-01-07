import pandas as pd
import pyodbc

# Step 1: Read data from Excel file into a Pandas DataFrame
excel_file_path = "path_to_your_excel_file.xlsx"  # Update with your file path
sheet_name = "Sheet1"  # Update with the name of your sheet (if applicable)

# Use pandas to read the Excel file
df = pd.read_excel(excel_file_path, sheet_name=sheet_name, engine='openpyxl')

print("Excel data loaded into DataFrame:")
print(df.head())

# Step 2: Connect to SQL Server
server = "your_server_name"  # Replace with your SQL Server name
database = "your_database_name"  # Replace with your database name
username = "your_username"  # Replace with your username
password = "your_password"  # Replace with your password

connection_string = (
    f"DRIVER={{ODBC Driver 17 for SQL Server}};"
    f"SERVER={server};"
    f"DATABASE={database};"
    f"UID={username};"
    f"PWD={password}"
)

try:
    conn = pyodbc.connect(connection_string)
    print("Connected to SQL Server successfully!")
except Exception as e:
    print("Error connecting to SQL Server:", e)
    exit()

# Step 3: Prepare the insert query
table_name = "your_table_name"  # Replace with your target table name

# Generate SQL query for inserting data
columns = ", ".join(df.columns)  # Generate column list for SQL
placeholders = ", ".join(["?" for _ in df.columns])  # Generate placeholders for values
insert_query = f"INSERT INTO {table_name} ({columns}) VALUES ({placeholders})"

# Convert DataFrame to a list of tuples for bulk insert
data = [tuple(row) for row in df.itertuples(index=False)]

# Step 4: Bulk insert using executemany()
try:
    cursor = conn.cursor()
    cursor.executemany(insert_query, data)
    conn.commit()
    print(f"Bulk insert into {table_name} completed successfully!")
except Exception as e:
    print("Error during bulk insert:", e)
finally:
    cursor.close()
    conn.close()

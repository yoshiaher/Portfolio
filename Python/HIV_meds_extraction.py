import pandas as pd  # Library for data manipulation and analysis
import requests  # Library for making HTTP requests
from bs4 import BeautifulSoup  # Library for parsing HTML and web scraping
import re  # Library for working with regular expressions


# Step 1: Fetch the web page
# URL of the page containing the FDA-approved HIV medicines
url = "https://hivinfo.nih.gov/understanding-hiv/fact-sheets/fda-approved-hiv-medicines"

# Send an HTTP GET request to fetch the HTML content of the web page
response = requests.get(url)

# Check if the request was successful (HTTP status code 200 means success)
if response.status_code == 200:
    # Step 2: Parse the HTML content of the page
    soup = BeautifulSoup(response.content, "html.parser")  # Parse the HTML using BeautifulSoup
    
    # Locate the table on the page
    table = soup.find("table")
    
    if table:
        # Step 3: Extract the table's content into a pandas DataFrame
        df = pd.read_html(str(table))[0]
    else:
        print("No table found on the web page.")  
else:
    print(f"Failed to fetch data. HTTP Status code: {response.status_code}")  # Handle request failure

# Remove the unnecessary first row:
df = df.iloc[1:]

# Reset the DataFrame index:
df = df.reset_index(drop=True)

# Remove the merged header row:
df = df.iloc[1:]

# Rename the columns for clarity and consistency:
# The columns are renamed to meaningful names that describe the data
df.columns = ['Drug Class', 'Generic Name', 'Brand Name', 'FDA Approval Date']

# Function to extract acronyms and remove parentheses from the text
def extract_acronyms(text):
    """
    This function extracts acronyms (text inside parentheses) and removes parentheses 
    from the original text.

    Parameters:
    - text (str): The input string to process.

    Returns:
    - tuple: (acronyms, text_without_parentheses)
        - acronyms: Comma-separated acronyms found in the text.
        - text_without_parentheses: The original text without the parentheses.
    """
    # Find all text inside parentheses and join it with a comma
    acronyms = re.findall(r'\(([^)]+)\)', text)
    
    # Remove all text inside parentheses (and the parentheses themselves) from the input text
    text_without_parentheses = re.sub(r'\([^)]*\)', '', text)
    
    return ', '.join(acronyms), text_without_parentheses

# Apply the `extract_acronyms` function to the 'Generic Name' column
# This splits the column into two new columns: 'Acronyms' and a cleaned 'Generic Name'
df[['Acronyms', 'Generic Name']] = df['Generic Name'].apply(extract_acronyms).apply(pd.Series)

# Create a new column 'Class' by copying the 'FDA Approval Date' column
# This is done to later differentiate between dates and drug classes
df['Class'] = df['FDA Approval Date']

# Helper function to determine if a value is a date
def is_date(value):
    """
    Checks if the given value contains a year (4 consecutive digits) and
    can be considered a date.

    Parameters:
    - value (str): The value to check.

    Returns:
    - bool: True if the value looks like a date, False otherwise.
    """
    return bool(re.search(r'\b\d{4}\b', str(value)))

# Initialize a variable to keep track of the current drug class
current_class = None

# Iterate through each row of the DataFrame to populate the 'Class' column
for index, row in df.iterrows():
    value = row['FDA Approval Date']  # Get the value in the 'FDA Approval Date' column
    if not is_date(value):  # If the value is not a date, it's a drug class
        current_class = value  # Update the current class
    df.at[index, 'Class'] = current_class  # Assign the current class to the 'Class' column

# Fill any empty rows in the 'Class' column with the default class:
# "Nucleoside Reverse Transcriptase Inhibitors (NRTIs)"
df['Class'] = df['Class'].apply(lambda x: 'Nucleoside Reverse Transcriptase Inhibitors (NRTIs)' if pd.isna(x) or x == '' else x)

# Remove rows where the 'FDA Approval Date' and 'Class' columns have the same value
# This is done to clean up rows that accidentally contain duplicate information
df = df[df['FDA Approval Date'] != df['Class']]

# Drop the 'Drug Class' column from the DataFrame
# The column might no longer be needed after processing
df = df.drop(columns=['Drug Class'])

# Clean the 'Generic Name' column:
# Remove any extraneous text that follows the actual generic name
df['Generic Name'] = df['Generic Name'].str.extract(r'([^\*]+)', expand=False)

# Save the cleaned DataFrame to an Excel file:
# The file is saved at the specified location
output_file = "/home/share/yaher/Python/NIH_APPROVED_MEDICINES.xlsx"
df.to_excel(output_file, index=False, header=True)  # Include column headers but exclude the index

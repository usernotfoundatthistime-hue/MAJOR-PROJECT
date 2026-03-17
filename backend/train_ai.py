import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.naive_bayes import MultinomialNB
import joblib

print("1. Downloading dataset...")
# Using a widely trusted public dataset for spam detection
url = "https://raw.githubusercontent.com/justmarkham/pycon-2016-tutorial/master/data/sms.tsv"
df = pd.read_csv(url, sep='\t', names=['label', 'message'])

print("2. Training AI model...")
# Convert text messages into numerical data
vectorizer = TfidfVectorizer()
X = vectorizer.fit_transform(df['message'])
y = df['label'] # 'spam' or 'ham' (safe)

# Train the Multinomial Naive Bayes model
model = MultinomialNB()
model.fit(X, y)

print("3. Saving model to disk...")
# Save the trained model and vectorizer so FastAPI can use them
joblib.dump(model, 'ai_model.pkl')
joblib.dump(vectorizer, 'ai_vectorizer.pkl')

print("✅ Done! 'ai_model.pkl' and 'ai_vectorizer.pkl' have been created.")
// Import required modules
const express = require('express');
const path = require('path');
 
 
// Create an Express application
const app = express();
 
 
// Define the path to the static website (change 'build' to your actual folder name)
const staticPath = path.join(__dirname, 'build');
 
 
// Set up middleware to serve static files
app.use(express.static(staticPath));
 
 
// Define a route to handle all other requests and serve the index.html file
app.get('*', (req, res) => {
  res.sendFile(path.join(staticPath, 'index.html'));
});
 
 
// Specify the port to listen on (change 3000 to your preferred port)
const port = 443;
 
 
// Start the server
app.listen(port, () => {
    console.log(`Server is running on port ${port}`);
});



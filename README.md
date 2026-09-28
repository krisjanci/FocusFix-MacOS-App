![FocusFix logo](Assets/FocusFixLong.png)

# FocusFix-MacOS-App
Evaluating Personalized Microbreaks to Reduce Mental Fatigue While Maintaining Productivity

## Workflow

1. External Data is used to train the machine learning model in python.

2. Convert the trained model to Core ML to run in swift.

3. The app will summarise activity every minute and pass it into the model.

4. THe model will give a fatigue, stress or workload prediction.

5. A seperate decision rule will use the prediction and things like time since last break to decide if it should recommend a break.

6. Later the new data can be used for retraining the model.



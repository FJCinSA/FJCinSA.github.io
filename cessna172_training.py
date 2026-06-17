class Cessna172Training:
    def __init__(self):
        self.ground_lessons = [
            "Aircraft Systems",
            "Flight Controls",
            "Engine Management",
            "Weather",
            "Navigation"
        ]

        self.flight_lessons = {
            "Lesson 1": "Preflight & Startup",
            "Lesson 2": "Taxi & Takeoff",
            "Lesson 3": "Straight & Level Flight",
            "Lesson 4": "Turns, Climbs, Descents",
            "Lesson 5": "Stall Recovery",
            "Lesson 6": "Pattern Work",
            "Lesson 7": "Landings"
        }

        self.checklists = {
            "preflight": [
                "Master Switch - OFF",
                "Fuel Quantity - CHECK",
                "Control Surfaces - CHECK",
                "Pitot Tube - CLEAR"
            ],
            "startup": [
                "Master Switch - ON",
                "Fuel Shutoff - ON",
                "Prime - AS REQUIRED",
                "Mixture - RICH",
                "Throttle - CRACK",
                "Prop Area - CLEAR"
            ]
        }

    def get_lesson_plan(self):
        return {
            "ground": self.ground_lessons,
            "flight": self.flight_lessons,
            "procedures": self.checklists
        }


def main():
    training = Cessna172Training()
    plan = training.get_lesson_plan()
    print("Cessna 172 Training Curriculum:")
    print("\nGround School:")
    for lesson in plan["ground"]:
        print(f"  - {lesson}")
    print("\nFlight Lessons:")
    for num, lesson in plan["flight"].items():
        print(f"  - {num}: {lesson}")
    print("\nChecklists:")
    for name, items in plan["procedures"].items():
        print(f"\n  {name.upper()}:")
        for item in items:
            print(f"    [ ] {item}")


if __name__ == "__main__":
    main()

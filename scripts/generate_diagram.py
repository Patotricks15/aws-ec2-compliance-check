"""Generate docs/architecture.drawio for the Compliance check demo.

Mirrors the AWS Cloud Quest reference layout: AWS Config invokes a custom Lambda
rule hourly, reports evaluation results back, and fires a "Trigger Event" that
EventBridge routes to Systems Manager. Systems Manager remediates/tags the
flagged EC2 instances (Agents) and publishes a Notifications email via SNS.
"""

import os

import drawpyo

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "..", "docs")

AWS4_BASE = (
    "sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;"
    "strokeColor=none;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;"
    "align=center;html=1;fontSize=11;fontStyle=0;aspect=fixed;pointerEvents=1;"
)


def aws_style(icon_name, fill_color):
    return f"{AWS4_BASE}fillColor={fill_color};shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{icon_name};"


def add_node(page, name, x, y, icon_name, fill_color, width=64, height=64):
    node = drawpyo.diagram.Object(page=page, value=name, position=(x, y))
    node.width = width
    node.height = height
    node.apply_style_string(aws_style(icon_name, fill_color))
    return node


def add_edge(page, source, target, label=None):
    edge = drawpyo.diagram.Edge(page=page, source=source, target=target, label=label)
    edge.waypoints = "orthogonal"
    edge.endArrow = "block"
    edge.startArrow = "none"
    edge.strokeColor = "#545B64"
    return edge


def build_diagram():
    file = drawpyo.File()
    file.file_name = "architecture.drawio"
    file.file_path = OUTPUT_DIR

    page = drawpyo.Page(file=file)
    page.name = "Compliance check"

    config = add_node(page, "AWS Config", 20, 220, "config", "#E7157B")
    rule_lambda = add_node(page, "Custom Rule\n(Lambda)", 280, 220, "lambda_function", "#ED7100")
    event_bridge = add_node(page, "EventBridge", 20, 480, "eventbridge", "#E7157B")
    systems_manager = add_node(page, "Systems\nManager", 280, 480, "systems_manager", "#E7157B")

    agent_active_1 = add_node(page, "EC2 Instance\n(Agent: Active)", 580, 300, "ec2", "#ED7100")
    agent_active_2 = add_node(page, "EC2 Instance\n(Agent: Active)", 580, 480, "ec2", "#ED7100")
    agent_inactive = add_node(page, "EC2 Instance\n(Agent: Inactive)", 580, 660, "ec2", "#ED7100")

    notifications = add_node(page, "Notifications", 280, 720, "sns", "#E7157B")

    add_edge(page, config, rule_lambda, label="Invoking custom rule / Results")
    add_edge(page, config, event_bridge, label="Trigger Event")
    add_edge(page, event_bridge, systems_manager)
    add_edge(page, systems_manager, agent_active_1, label="Agent: Active")
    add_edge(page, systems_manager, agent_active_2, label="Agent: Active")
    add_edge(page, systems_manager, agent_inactive, label="Agent: Inactive")
    add_edge(page, systems_manager, notifications, label="Notifications")

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    file.write()
    print(f"Wrote {os.path.join(OUTPUT_DIR, file.file_name)}")


if __name__ == "__main__":
    build_diagram()
